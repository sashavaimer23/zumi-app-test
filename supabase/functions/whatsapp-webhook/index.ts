// Zumi — приём сообщений WhatsApp (подтверждение номера).
// Человек нажимает в Zumi «Confirm with WhatsApp» и отправляет нам «Zumi code 123456».
// Meta пересылает сообщение сюда → confirm_whatsapp_code() подтверждает номер, с которого написали.
//
// Секреты (Supabase → Edge Functions → Secrets):
//   WA_VERIFY_TOKEN — любая длинная строка; та же строка в Meta → WhatsApp → Configuration → Verify token
//   WA_APP_SECRET   — Meta → App settings → Basic → App secret (проверка, что сообщение пришло от Meta)
//   WA_TOKEN        — (необязательно) ключ доступа WhatsApp, чтобы ответить человеку «номер подтверждён»
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам.
// Настройка функции: «Verify JWT» — ВЫКЛЮЧЕНО (Meta не присылает ключ Supabase).

import { createClient } from "jsr:@supabase/supabase-js@2";

const VERIFY_TOKEN = (Deno.env.get("WA_VERIFY_TOKEN") ?? "").trim();
const APP_SECRET = (Deno.env.get("WA_APP_SECRET") ?? "").trim();
const WA_TOKEN = (Deno.env.get("WA_TOKEN") ?? "").trim();
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const REPLIES: Record<string, string> = {
  ok: "✅ Your number is confirmed on Zumi. You can go back to the app.",
  taken:
    "This number is already confirmed on another Zumi account. One number can belong to one account. " +
    "Please sign in to that account or contact Zumi support.",
  expired: "This code is not valid or has expired. Open Zumi and tap “Confirm with WhatsApp” again.",
};

async function signatureOk(raw: string, header: string | null): Promise<boolean> {
  if (!APP_SECRET || !header?.startsWith("sha256=")) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(APP_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)));
  const hex = Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
  const got = header.slice(7);
  if (got.length !== hex.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ got.charCodeAt(i);
  return diff === 0;
}

async function reply(phoneNumberId: string, to: string, text: string) {
  if (!WA_TOKEN) return; // ответ — по желанию; номер подтверждается и без него
  try {
    const r = await fetch(`https://graph.facebook.com/v22.0/${phoneNumberId}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${WA_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ messaging_product: "whatsapp", to, type: "text", text: { body: text } }),
    });
    if (!r.ok) console.warn("whatsapp-webhook: reply failed", r.status, (await r.text()).slice(0, 300));
  } catch (_) { /* не мешаем подтверждению */ }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Meta проверяет адрес при подключении вебхука
  if (req.method === "GET") {
    const ok = url.searchParams.get("hub.mode") === "subscribe" && VERIFY_TOKEN &&
      url.searchParams.get("hub.verify_token") === VERIFY_TOKEN;
    return ok
      ? new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 })
      : new Response("Forbidden", { status: 403 });
  }
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const raw = await req.text();
  if (!(await signatureOk(raw, req.headers.get("x-hub-signature-256")))) {
    // чаще всего — в WA_APP_SECRET вставлен не «Секрет приложения» или он скопирован не полностью
    console.warn("whatsapp-webhook: bad signature", { hasSecret: APP_SECRET.length > 0, secretLength: APP_SECRET.length });
    return new Response("Bad signature", { status: 401 });
  }

  let body: any;
  try {
    body = JSON.parse(raw);
  } catch {
    return new Response("ok");
  }

  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      const value = change?.value ?? {};
      const phoneNumberId: string = value?.metadata?.phone_number_id ?? "";
      for (const m of value?.messages ?? []) {
        if (m?.type !== "text" || !m?.from) continue;
        const text: string = m.text?.body ?? "";
        if (!/\d{6}/.test(text)) continue; // обычные сообщения не трогаем
        const { data, error } = await db.rpc("confirm_whatsapp_code", { p_text: text, p_from: m.from });
        if (error) {
          console.error("confirm_whatsapp_code failed", error.message);
          continue;
        }
        console.log("whatsapp-webhook: code message", { result: data });
        const msg = REPLIES[String(data)] ?? REPLIES.expired;
        if (phoneNumberId) await reply(phoneNumberId, m.from, msg);
      }
    }
  }
  // всегда 200 — иначе Meta будет присылать сообщение повторно
  return new Response("ok");
});
