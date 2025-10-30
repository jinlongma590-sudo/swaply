// supabase/functions/send-verification-email/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// === 环境变量 ===
const RESEND_API_KEY     = Deno.env.get("RESEND_API_KEY");
const SENDGRID_API_KEY   = Deno.env.get("SENDGRID_API_KEY");
const EMAIL_FROM         = Deno.env.get("EMAIL_FROM") ?? "onboarding@resend.dev";
const SUPABASE_URL       = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE       = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 仅在 Edge Function 内部使用 service_role
const sb = createClient(SUPABASE_URL, SERVICE_ROLE);

// === 请求体 ===
interface EmailRequest {
  email: string;
  template?: string;
  name?: string;
}

serve(async (req) => {
  // CORS 预检
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors() });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const { email, name }: EmailRequest = await req.json();
    if (!email) return json({ error: "Email is required" }, 400);

    // 1) 生成 6 位验证码 + 10 分钟过期时间
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expires_at = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    // 2) 写库（保证 email 唯一）
    const { error: upErr } = await sb
      .from("email_verifications")
      .upsert({ email, code, expires_at }, { onConflict: "email" });
    if (upErr) throw new Error(`db upsert failed: ${upErr.message}`);

    // 3) 发邮件（Resend 优先，其次 SendGrid；本地/未配置则打印）
    let sent = false;
    if (RESEND_API_KEY) {
      sent = await sendWithResend(email, code, name);
    } else if (SENDGRID_API_KEY) {
      sent = await sendWithSendGrid(email, code, name);
    } else {
      console.log(`DEV ONLY -> send code to ${email}: ${code}`);
      sent = true;
    }
    if (!sent) throw new Error("provider send failed");

    return json({ success: true, message: "Verification email sent" });
  } catch (e) {
    console.error("[send-verification-email] error:", e);
    return json({ error: "Failed to send verification email", details: String(e) }, 500);
  }
});

// === 工具函数 ===
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
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

// === Resend ===
async function sendWithResend(email: string, code: string, name?: string): Promise<boolean> {
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `Swaply <${EMAIL_FROM}>`,
        to: [email],
        subject: "Verify your email address",
        html: getEmailTemplate({ code, name: name ?? "User", email }),
      }),
    });
    if (!r.ok) {
      console.error("Resend error:", r.status, await r.text());
    }
    return r.ok;
  } catch (err) {
    console.error("Resend fetch error:", err);
    return false;
  }
}

// === SendGrid(备用) ===
async function sendWithSendGrid(email: string, code: string, name?: string): Promise<boolean> {
  try {
    const r = await fetch("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${SENDGRID_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        personalizations: [
          { to: [{ email, name: name ?? "User" }], subject: "Verify your email address" },
        ],
        from: { email: EMAIL_FROM, name: "Swaply" },
        content: [{ type: "text/html", value: getEmailTemplate({ code, name: name ?? "User", email }) }],
      }),
    });
    if (!r.ok) {
      console.error("SendGrid error:", r.status, await r.text());
    }
    return r.ok;
  } catch (err) {
    console.error("SendGrid fetch error:", err);
    return false;
  }
}

// === 邮件模板 ===
function getEmailTemplate({ code, name, email }: { code: string; name: string; email?: string }) {
  return `
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Verify Your Email - Swaply</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Oxygen,Ubuntu,Cantarell,sans-serif;background:#f5f5f5;padding:20px}
  .container{max-width:600px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,.1)}
  .header{background:linear-gradient(135deg,#2196F3,#1976D2);color:#fff;padding:40px 30px;text-align:center}
  .header h1{font-size:28px;font-weight:700;margin:0 0 8px}
  .content{padding:40px 30px}
  .greeting{font-size:18px;margin:0 0 20px;color:#333}
  .message{font-size:16px;line-height:1.6;color:#555;margin:0 0 30px}
  .code-container{background:#f8f9fa;border:2px dashed #2196F3;border-radius:8px;padding:20px;text-align:center;margin:30px 0}
  .code{font-family:Monaco,Menlo,'Ubuntu Mono',monospace;font-size:32px;font-weight:700;color:#2196F3;letter-spacing:4px;margin:10px 0}
  .code-label{font-size:14px;color:#666;margin:0 0 10px}
  .expiry{font-size:12px;color:#888;margin-top:10px}
  .footer{background:#f8f9fa;padding:20px 30px;text-align:center;border-top:1px solid #eee}
  .footer p{font-size:14px;color:#666;margin:0 0 10px}
  .security-note{background:#fff3cd;border:1px solid #ffeaa7;border-radius:6px;padding:15px;margin:20px 0;font-size:14px;color:#856404}
  .security-note strong{display:block;margin-bottom:5px}
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🟟 Email Verification</h1>
      <p>Swaply Account Security</p>
    </div>
    <div class="content">
      <p class="greeting">Hello ${name},</p>
      <p class="message">
        Thank you for signing up with Swaply! Please enter the verification code below in the app to verify your email.
      </p>
      <div class="code-container">
        <p class="code-label">Your Verification Code:</p>
        <div class="code">${code}</div>
        <p class="expiry">This code will expire in 10 minutes.</p>
      </div>
      <p class="message">
        If you didn't request this code, you can safely ignore this email.
      </p>
      <div class="security-note">
        <strong>Security Notice:</strong>
        Never share this code with anyone. Swaply staff will never ask for it.
      </div>
    </div>
    <div class="footer">
      <p><strong>Swaply Team</strong></p>
      ${email ? `<p style="font-size:12px;color:#888">Sent to ${email}</p>` : ``}
    </div>
  </div>
</body>
</html>`;
}