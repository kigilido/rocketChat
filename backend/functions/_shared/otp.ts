/**
 * Shared helpers for the phone one-time-passcode sign-in flow.
 */

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Normalise user input to a compact E.164 string (`+` followed by digits).
 * Returns null when the result cannot plausibly be a phone number.
 */
export function normalizePhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  const digits = trimmed.replace(/[^\d]/g, "");
  if (digits.length < 7 || digits.length > 15) return null;
  return `+${digits}`;
}

/** Deterministic login email derived from the phone number. */
export function emailForPhone(phone: string): string {
  return `${phone.replace(/[^\d]/g, "")}@phone.tagchat.app`;
}

const encoder = new TextEncoder();

/** SHA-256 of the code, peppered with a server-only secret. */
export async function hashCode(phone: string, code: string): Promise<string> {
  const pepper = Deno.env.get("OTP_PEPPER") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(`${phone}:${code}:${pepper}`));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Cryptographically random 6-digit code. */
export function generateCode(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return (buf[0] % 1_000_000).toString().padStart(6, "0");
}

/** Constant-time string comparison to avoid leaking the digest byte by byte. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Deliver the code over SMS when Twilio credentials are configured.
 * Returns false when no provider is set up, in which case the caller falls back
 * to returning the code to the client so the flow is still testable.
 */
export async function sendSms(phone: string, body: string): Promise<boolean> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_FROM_NUMBER");
  if (!sid || !token || !from) return false;

  const params = new URLSearchParams({ To: phone, From: from, Body: body });
  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!res.ok) {
    console.error("Twilio send failed", res.status, await res.text());
    return false;
  }
  return true;
}
