import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  corsHeaders,
  emailForPhone,
  hashCode,
  json,
  normalizePhone,
  timingSafeEqual,
} from "../_shared/otp.ts";

const MAX_ATTEMPTS = 5;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = (await req.json().catch(() => ({}))) as { phone?: unknown; code?: unknown };
    const phone = normalizePhone(payload.phone);
    const code = typeof payload.code === "string" ? payload.code.replace(/[^\d]/g, "") : "";

    if (!phone || code.length !== 6) {
      return json({ error: "Enter the 6-digit code we sent you." }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: record } = await admin
      .from("otp_codes")
      .select("code_hash, attempts, expires_at")
      .eq("phone", phone)
      .maybeSingle();

    if (!record) {
      return json({ error: "That code has expired. Request a new one." }, 400);
    }

    if (new Date(record.expires_at).getTime() < Date.now()) {
      await admin.from("otp_codes").delete().eq("phone", phone);
      return json({ error: "That code has expired. Request a new one." }, 400);
    }

    if (record.attempts >= MAX_ATTEMPTS) {
      await admin.from("otp_codes").delete().eq("phone", phone);
      return json({ error: "Too many attempts. Request a new code." }, 429);
    }

    const candidate = await hashCode(phone, code);
    if (!timingSafeEqual(candidate, record.code_hash)) {
      await admin
        .from("otp_codes")
        .update({ attempts: record.attempts + 1 })
        .eq("phone", phone);
      return json({ error: "That code isn't right. Try again." }, 400);
    }

    await admin.from("otp_codes").delete().eq("phone", phone);

    // Exchange the verified phone for a real Supabase session. The account is
    // keyed to a deterministic internal email so no mailbox is ever involved.
    const email = emailForPhone(phone);
    let isNewUser = false;

    let linkResult = await admin.auth.admin.generateLink({ type: "magiclink", email });

    if (linkResult.error) {
      const { error: createError } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: { phone },
      });

      if (createError && !`${createError.message}`.toLowerCase().includes("already")) {
        console.error("Failed to create user", createError);
        return json({ error: "Could not complete sign in. Try again." }, 500);
      }

      isNewUser = !createError;
      linkResult = await admin.auth.admin.generateLink({ type: "magiclink", email });
    }

    const tokenHash = linkResult.data?.properties?.hashed_token;
    if (linkResult.error || !tokenHash) {
      console.error("Failed to mint session token", linkResult.error);
      return json({ error: "Could not complete sign in. Try again." }, 500);
    }

    return json({ tokenHash, isNewUser });
  } catch (err) {
    console.error("verify-otp failed", err);
    return json({ error: "Could not complete sign in. Try again." }, 500);
  }
});
