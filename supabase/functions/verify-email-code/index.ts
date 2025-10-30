// supabase/functions/verify-email-code/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---- ENV ----
const SUPABASE_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SUPABASE_URL, SERVICE_ROLE);

interface Payload {
  email: string;
  code: string;
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors() });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed" }, 405);
  }

  try {
    const { email, code }: Payload = await req.json();
    if (!email || !code) return json({ ok: false, reason: "missing_params" }, 400);

    // 1) 读取验证码记录
    const { data, error } = await sb
      .from("email_verifications")
      .select("code, expires_at")
      .eq("email", email)
      .single();

    if (error || !data) return json({ ok: false, reason: "not_found" }, 400);

    // 2) 校验过期 & 匹配
    const now = new Date();
    const exp = new Date(data.expires_at as string);
    if (now > exp) return json({ ok: false, reason: "expired" }, 400);
    if (data.code !== code) return json({ ok: false, reason: "mismatch" }, 400);

    // 3) 标记用户已验证（如果有 profiles 表则更新；没有就忽略该步骤）
    try {
      await sb
        .from("profiles")
// LEGACY REMOVED:         .update({ email_verified: true, email_verified_at: new Date().toISOString() })
        .eq("email", email);
    } catch (_e) {
      // profiles 不存在时静默跳过
    }

    // 4) 一次性验证码：验证成功后删除 / 失效当前记录
    await sb.from("email_verifications").delete().eq("email", email);

    return json({ ok: true, message: "Email verified successfully" });
  } catch (e) {
    console.error("[verify-email-code] error:", e);
    return json({ ok: false, error: String(e) }, 500);
  }
});

// ---- helpers ----
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors(), "Content-Type": "application/json" },
  });
}

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}
