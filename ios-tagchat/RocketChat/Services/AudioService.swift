//
//  AudioService.swift
//  RocketChat
//

import Foundation
import AVFoundation
import SwiftUI

/// Manages voice note recording and playback. Supports optional voice
/// masking via real-time pitch shifting with AVAudioEngine.
@Observable
final class AudioService: NSObject, AVAudioRecorderDelegate {
    // Recording state
    var isRecording = false
    var recordingDuration: TimeInterval = 0

    // Playback state
    var isPlaying = false
    var playingProgress: Double = 0
    var playingDuration: TimeInterval = 0
    var playingMessageId: UUID?

    // Settings
    var voiceMaskingEnabled: Bool {
        didSet { defaults.set(voiceMaskingEnabled, forKey: maskingKey) }
    }

    private let defaults = UserDefaults.standard
    private let maskingKey = "tagchat.voiceMasking"

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var pitchUnit: AVAudioUnitTimePitch?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var currentAudioURL: URL?
    private var recordedDuration: TimeInterval = 0

    override init() {
        voiceMaskingEnabled = defaults.bool(forKey: maskingKey)
        super.init()
    }

    // MARK: - Recording

    /// Start recording a new voice note. Returns the file URL the audio
    /// will be written to, or nil on failure.
    func startRecording() -> URL? {
        do {
            try configureSession(active: true)
        } catch {
            return nil
        }

        let fileName = "voice_\(UUID().uuidString).m4a"
        let url = audioURL(for: fileName)
        currentAudioURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            isRecording = true
            recordingDuration = 0
            startRecordingTimer()
            return url
        } catch {
            try? deactivateSession()
            return nil
        }
    }

    /// Stop recording and return the file URL + duration. Returns nil if the
    /// recording was too short (< 0.5s).
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }
        recorder?.stop()
        stopRecordingTimer()
        isRecording = false

        let duration = recordingDuration
        guard duration >= 0.5, let url = currentAudioURL else {
            try? deactivateSession()
            return nil
        }

        recordedDuration = duration
        try? deactivateSession()
        return (url, duration)
    }

    /// Cancel the current recording and delete the file.
    func cancelRecording() {
        guard isRecording else { return }
        recorder?.stop()
        stopRecordingTimer()
        isRecording = false

        if let url = currentAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentAudioURL = nil
        try? deactivateSession()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        stopRecordingTimer()
    }

    // MARK: - Playback

    /// Toggle play/pause for a voice note. Uses AVAudioEngine with pitch
    /// shifting when voice masking is enabled.
    func togglePlayback(url: URL, messageId: UUID) {
        if isPlaying && playingMessageId == messageId {
            stopPlayback()
            return
        }

        stopPlayback()

        if voiceMaskingEnabled {
            playWithEngine(url: url, messageId: messageId)
        } else {
            playWithPlayer(url: url, messageId: messageId)
        }
    }

    func stopPlayback() {
        playerNode?.stop()
        player?.stop()
        engine?.stop()
        engine?.reset()
        playbackTimer?.invalidate()
        playbackTimer = nil

        isPlaying = false
        playingProgress = 0
        playingDuration = 0
        playingMessageId = nil
        player = nil
        playerNode = nil
        pitchUnit = nil
        engine = nil
    }

    // MARK: - File Management

    /// Documents-directory URL for a given audio file name.
    func audioURL(for fileName: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    /// Delete an audio file from disk.
    func deleteAudio(fileName: String) {
        let url = audioURL(for: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func playWithPlayer(url: URL, messageId: UUID) {
        do {
            try configureSession(active: true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            playingDuration = player?.duration ?? 0
            playingMessageId = messageId
            isPlaying = true
            player?.play()
            startPlaybackTimer()
        } catch {
            try? deactivateSession()
        }
    }

    private func playWithEngine(url: URL, messageId: UUID) {
        do {
            try configureSession(active: true)

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            let pitchUnit = AVAudioUnitTimePitch()
            pitchUnit.pitch = -400 // lower pitch for masking

            engine.attach(playerNode)
            engine.attach(pitchUnit)
            engine.connect(playerNode, to: pitchUnit, format: nil)
            engine.connect(pitchUnit, to: engine.mainMixerNode, format: nil)

            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            playingDuration = duration
            playingMessageId = messageId
            isPlaying = true

            playerNode.scheduleFile(file, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.stopPlayback()
                    try? self?.deactivateSession()
                }
            }

            self.engine = engine
            self.playerNode = playerNode
            self.pitchUnit = pitchUnit

            try engine.start()
            playerNode.play()
            startPlaybackTimer()
        } catch {
            try? deactivateSession()
        }
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }

            if let player = self.player {
                let current = player.currentTime
                self.playingProgress = self.playingDuration > 0
                    ? min(1, current / self.playingDuration)
                    : 0
                if !player.isPlaying && self.isPlaying {
                    self.stopPlayback()
                }
            } else if let playerNode = self.playerNode,
                      let engine = self.engine, engine.isRunning {
                if let time = playerNode.lastRenderTime,
                   let playerTime = playerNode.playerTime(forNodeTime: time) {
                    let current = Double(playerTime.sampleTime) / playerTime.sampleRate
                    self.playingProgress = self.playingDuration > 0
                        ? min(1, current / self.playingDuration)
                        : 0
                }
            }
        }
    }

    private func configureSession(active: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if active {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } else {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func deactivateSession() throws {
        try configureSession(active: false)
    }
}
