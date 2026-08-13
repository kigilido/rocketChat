//
//  SupabaseService.swift
//  RocketChat
//
//  Single shared Supabase client. Native Supabase Auth mode: the SDK owns the
//  session, so no `accessToken` closure is supplied (that would disable
//  `supabase.auth.*`, which the phone sign-in flow depends on).
//

import Foundation
import Supabase

nonisolated enum SupabaseService {
    static let client: SupabaseClient = {
        guard let url = URL(string: Config.EXPO_PUBLIC_SUPABASE_URL) else {
            fatalError("EXPO_PUBLIC_SUPABASE_URL is missing or malformed")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: Config.EXPO_PUBLIC_SUPABASE_ANON_KEY
        )
    }()
}

/// Convenience accessor used across services.
nonisolated var supabase: SupabaseClient { SupabaseService.client }
