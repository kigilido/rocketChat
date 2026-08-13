import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  generateCode,
  hashCode,
  json,
  normalizePhone,
  sendSms,
} from "../_shared/otp.ts";

const CODE_TTL_SECONDS = 600;
const RESEND_COOLDOWN_SECONDS = 30;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const phone = normalizePhone((payload as { phone?: unknown }).phone);
    if (!phone) {
      return json({ error: "Enter a valid phone number." }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: existing } = await admin
      .from("otp_codes")
      .select("created_at")
      .eq("phone", phone)
      .maybeSingle();

    if (existing?.created_at) {
      const elapsed = (Date.now() - new Date(existing.created_at).getTime()) / 1000;
      if (elapsed < RESEND_COOLDOWN_SECONDS) {
        return json(
          { error: `Hold on — you can request another code in ${Math.ceil(RESEND_COOLDOWN_SECONDS - elapsed)}s.` },
          429,
        );
      }
    }

    const code = generateCode();
    const codeHash = await hashCode(phone, code);
    const expiresAt = new Date(Date.now() + CODE_TTL_SECONDS * 1000).toISOString();

    const { error: upsertError } = await admin.from("otp_codes").upsert({
      phone,
      code_hash: codeHash,
      attempts: 0,
      expires_at: expiresAt,
      created_at: new Date().toISOString(),
    });

    if (upsertError) {
      console.error("Failed to store OTP", upsertError);
      return json({ error: "Could not start verification. Try again." }, 500);
    }

    const delivered = await sendSms(phone, `${code} is your TagChat verification code.`);

    // Without an SMS provider configured the code is returned so the flow stays
    // usable end to end. Add TWILIO_* secrets to switch to real delivery.
    return json({ sent: true, delivered, devCode: delivered ? null : code });
  } catch (err) {
    console.error("request-otp failed", err);
    return json({ error: "Could not start verification. Try again." }, 500);
  }
});
