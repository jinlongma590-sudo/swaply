// supabase/functions/delete_account/index.ts
// Runtime: Deno (Supabase Edge Functions)
//
// 必需 Secrets：SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY
// 行为：校验 Authorization、二次验证密码、幂等清理数据与存储，最后删除 auth.users。

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// === 如与实际不符请修改 ===
const BUCKET_AVATARS = "avatars";   // 头像：avatars/<uid>/*
const BUCKET_LISTINGS = "listings"; // 商品图：listings/<listing_id>/*

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** 删除 bucket 下某个“文件夹”中当前层级的所有文件（幂等）。 */
async function deleteFolderLevel(
  supa: ReturnType<typeof createClient>,
  bucket: string,
  folder: string, // 例：`${uid}` 或 `${listingId}`
) {
  try {
    const { data, error } = await supa.storage.from(bucket).list(folder);
    if (error) return;
    const files = (data ?? [])
      .filter((f) => f.name && !f.name.endsWith("/"))
      .map((f) => `${folder}/${f.name}`);
    if (files.length) await supa.storage.from(bucket).remove(files);
  } catch { /* ignore */ }
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  if (!url || !serviceKey || !anonKey) return json({ error: "Missing function secrets" }, 500);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401);

  const body = await req.json().catch(() => ({}));
  if (!body?.confirm) return json({ error: "Bad Request" }, 400);

  const password = String(body?.password ?? "").trim();
  if (!password) return json({ error: "Password required" }, 400);

  // 用 Service Role，透传用户 JWT（便于 getUser）
  const supa = createClient(url, serviceKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // 当前用户
  const { data: userResp, error: getUserErr } = await supa.auth.getUser();
  if (getUserErr || !userResp?.user) return json({ error: "Unauthorized" }, 401);
  const uid = userResp.user.id;
  const email = userResp.user.email ?? "";
  if (!email) return json({ error: "Password check failed" }, 403);

  // 二次验证密码（使用 anon）
  const anon = createClient(url, anonKey);
  const signin = await anon.auth.signInWithPassword({ email, password });
  if (signin.error) return json({ error: "Wrong password" }, 403);

  // 1) 预取用户所有 listing_id
  const listingsIds = await supa.from("listings").select("id").eq("user_id", uid);
  const listingIdArr = (listingsIds.data ?? []).map((r: any) => r.id as string);

  // 2) 清理存储
  await deleteFolderLevel(supa, BUCKET_AVATARS, `${uid}`); // avatars/<uid>/*
  for (const lid of listingIdArr) {
    await deleteFolderLevel(supa, BUCKET_LISTINGS, `${lid}`); // listings/<listing_id>/*
  }

  // 3) 清理行数据（幂等，表/列缺失自动忽略）
  const tablesByUser = [
    "notifications",
    "favorites",
    "coupon_usages",
    "coupons",
    "pinned_ads",
    "active_pinned_ads",
    "search_pins",
    "search_pins_active",
    "user_tasks",
    "referrals",
    "device_tokens",
    "listing_views",
    "blocks",
  ];
  for (const t of tablesByUser) {
    const r = await supa.from(t).delete().eq("user_id", uid);
    if (r.error && !`${r.error.message}`.includes("relation")) {
      // 可按需记录：console.warn(`[${t}]`, r.error);
    }
  }

  // messages（sender/receiver 双列）
  try {
    await supa.from("messages").delete().or(`sender_id.eq.${uid},receiver_id.eq.${uid}`);
  } catch {}

  // listings（最后删，避免前面引用）
  try { await supa.from("listings").delete().eq("user_id", uid); } catch {}

  // profiles
  try { await supa.from("profiles").delete().eq("user_id", uid); } catch {}

  // 审计类匿名化（保留汇总、移除标识）
  try { await supa.from("reward_logs").update({ user_id: null }).eq("user_id", uid); } catch {}
  try {
    await supa
      .from("reports")
      .update({ reporter_id: null, reported_user_id: null })
      .or(`reporter_id.eq.${uid},reported_user_id.eq.${uid}`);
  } catch {}

  // 4) 删除 auth.users（用 admin，不带用户 JWT）
  const admin = createClient(url, serviceKey);
  const del = await admin.auth.admin.deleteUser(uid);
  if (del.error) return json({ error: del.error.message ?? "auth delete failed" }, 500);

  return json({ ok: true, user_id: uid });
});
