// Zumi — письма-уведомления (email alerts).
// Раз в 10 минут база (pg_cron, миграция 031) зовёт эту функцию → берём список email_due()
// → отправляем письма → отмечаем email_mark(). GET ?u=…&t=… — ссылка «Unsubscribe» из письма.
//
// Как создать (один раз): Supabase → Edge Functions → Deploy a new function → «Via Editor»,
// имя email-notify, вставить этот код, Deploy. В настройках функции «Verify JWT» — ВЫКЛЮЧИТЬ.
// Secrets (Edge Functions → Secrets):
//   SMTP_USER = zumi.team.zm@gmail.com
//   SMTP_PASS = пароль приложения Gmail (16 букв, без пробелов) — вводишь сама, никому не отправляешь
// После покупки домена можно перейти на Resend: RESEND_API_KEY + EMAIL_FROM (например "Zumi <hello@zumihome.com>").

import { createClient } from "jsr:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const SMTP_USER = (Deno.env.get("SMTP_USER") ?? "").trim();
const SMTP_PASS = (Deno.env.get("SMTP_PASS") ?? "").replace(/\s+/g, "");
const RESEND_KEY = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
const FROM = (Deno.env.get("EMAIL_FROM") ?? "").trim() || `Zumi <${SMTP_USER}>`;
const FN_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/email-notify`;

type Item = {
  user_id: string; kind: string; ref_id: string; email: string; name: string; token: string;
  data: Record<string, any>;
};

async function setting(key: string): Promise<string> {
  const { data } = await db.from("app_settings").select("value").eq("key", key).maybeSingle();
  return (data?.value as string) ?? "";
}

const esc = (s: unknown) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// ---------- тексты писем ----------
function compose(it: Item, site: string): { subject: string; title: string; body: string; button: string; link: string } {
  const d = it.data ?? {};
  switch (it.kind) {
    case "chat": {
      const n = Number(d.count ?? 1);
      return {
        subject: `${d.from} sent you ${n > 1 ? `${n} messages` : "a message"} on Zumi`,
        title: `New message from ${d.from}`,
        body: `About <b>${esc(d.title)}</b>:<br><br><i>“${esc(d.snippet)}”</i>`,
        button: "Reply on Zumi",
        link: `${site}/?open=chats`,
      };
    }
    case "support":
      return {
        subject: "Zumi support replied to you",
        title: "We answered your question",
        body: `<b>${esc(d.subject)}</b><br><br><i>“${esc(d.snippet)}”</i>`,
        button: "Open the reply",
        link: `${site}/?open=support`,
      };
    case "approved":
      return {
        subject: "Your listing is live on Zumi",
        title: "Your listing is live 🎉",
        body: `<b>${esc(d.title)}</b> passed our check and people can see it now. Share it to get your first calls faster.`,
        button: "See your listing",
        link: `${site}/?listing=${d.listing_id}`,
      };
    case "not_approved":
      return {
        subject: "Your listing needs a few changes",
        title: "Your listing was not approved yet",
        body: `<b>${esc(d.title)}</b><br><br>Reason: ${esc(d.note)}<br><br>Fix it and post it again — we check new listings quickly.`,
        button: "Open my listings",
        link: `${site}/?open=listings`,
      };
    case "confirm": {
      const n = Number(d.count ?? 1);
      const hide = `${d.hide_in} ${Number(d.hide_in) === 1 ? "day" : "days"}`;
      return n > 1
        ? {
          subject: `Are your ${n} listings still available?`,
          title: `${n} listings need a quick answer`,
          body: `Tap <b>Yes</b> on the ones still free, or <b>No</b> on those already taken. ` +
            `Listings without an answer are paused (hidden from search) in ${hide}. It takes a minute.`,
          button: "Answer now",
          link: `${site}/?open=listings`,
        }
        : {
          subject: "Is your property still available?",
          title: "Is it still available?",
          body: `<b>${esc(d.title)}</b><br><br>Tap <b>Yes</b> to keep it in search, or <b>No</b> if it is already taken. ` +
            `Without an answer it will be paused (hidden from search) in ${hide}.`,
          button: "Answer in one tap",
          link: `${site}/?listing=${d.listing_id}`,
        };
    }
    case "plan_ending": {
      const name = ({ pro: "Pro", agency: "Agency", landlord: "Landlord" } as Record<string, string>)[d.plan] ?? "Zumi";
      const days = Number(d.days ?? 1);
      return {
        subject: `Your ${name} plan ends in ${days} ${days === 1 ? "day" : "days"}`,
        title: `Your ${name} plan ends on ${esc(d.until)}`,
        body: `Renew to keep posting above your free limit and to get your monthly boosts. ` +
          `Your listings stay up either way — we never remove them.<br><br>` +
          `Tip: pay for 3, 6 or 12 months and save up to 17%.`,
        button: "Renew my plan",
        link: `${site}/?open=plans`,
      };
    }
    default:
      return { subject: "News from Zumi", title: "Zumi", body: "", button: "Open Zumi", link: site };
  }
}

function html(it: Item, c: ReturnType<typeof compose>, unsub: string): string {
  return `<!doctype html><html><body style="margin:0;background:#F6F1EA;font-family:Arial,Helvetica,sans-serif;color:#1F2A26">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F1EA;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:18px;padding:28px">
<tr><td style="font-size:22px;font-weight:bold;color:#2F5248;letter-spacing:2px">ZUMI</td></tr>
<tr><td style="padding-top:18px;font-size:20px;font-weight:bold">${esc(c.title)}</td></tr>
<tr><td style="padding-top:10px;font-size:15px;line-height:1.5">Hi ${esc(it.name)},<br><br>${c.body}</td></tr>
<tr><td style="padding-top:22px"><a href="${c.link}" style="display:inline-block;background:#F07A5A;color:#ffffff;text-decoration:none;font-weight:bold;padding:13px 24px;border-radius:24px">${esc(c.button)}</a></td></tr>
<tr><td style="padding-top:26px;font-size:12px;color:#7A857F;line-height:1.5">Never pay before you have seen a property in person.<br>
You get this email because you have a Zumi account. <a href="${unsub}" style="color:#7A857F">Unsubscribe</a> or turn alerts off in Settings.</td></tr>
</table></td></tr></table></body></html>`;
}

function text(it: Item, c: ReturnType<typeof compose>, unsub: string): string {
  const plain = c.body.replace(/<br>/g, "\n").replace(/<[^>]+>/g, "").replace(/&quot;/g, '"').replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  return `Hi ${it.name},\n\n${c.title}\n\n${plain}\n\n${c.button}: ${c.link}\n\n—\nZumi · Unsubscribe: ${unsub}`;
}

// ---------- отправка ----------
async function sendAll(items: Item[], site: string) {
  let smtp: SMTPClient | null = null;
  if (!RESEND_KEY) {
    smtp = new SMTPClient({
      connection: { hostname: "smtp.gmail.com", port: 465, tls: true, auth: { username: SMTP_USER, password: SMTP_PASS } },
    });
  }
  let sent = 0, failed = 0;
  for (const it of items) {
    const c = compose(it, site);
    const unsub = `${FN_URL}?u=${it.user_id}&t=${it.token}`;
    try {
      if (RESEND_KEY) {
        const r = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { Authorization: `Bearer ${RESEND_KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: FROM, to: [it.email], subject: c.subject, html: html(it, c, unsub), text: text(it, c, unsub),
            headers: { "List-Unsubscribe": `<${unsub}>` },
          }),
        });
        if (!r.ok) throw new Error(`resend ${r.status}: ${(await r.text()).slice(0, 200)}`);
      } else {
        await smtp!.send({
          from: FROM, to: it.email, subject: c.subject,
          content: text(it, c, unsub), html: html(it, c, unsub),
          headers: { "List-Unsubscribe": `<${unsub}>` },
        });
      }
      await db.rpc("email_mark", { p_user: it.user_id, p_kind: it.kind, p_ref: it.ref_id, p_ok: true });
      sent++;
    } catch (e) {
      failed++;
      console.error("email failed", it.kind, String(e));
      await db.rpc("email_mark", { p_user: it.user_id, p_kind: it.kind, p_ref: it.ref_id, p_ok: false, p_error: String(e) });
      if (/auth|535|534|Username and Password/i.test(String(e))) break; // неверный пароль — не мучаем остальных
    }
  }
  try { await smtp?.close(); } catch { /* ignore */ }
  return { sent, failed };
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // ссылка «Unsubscribe»
  if (req.method === "GET" && url.searchParams.get("u")) {
    const { data } = await db.rpc("email_unsubscribe", {
      p_user: url.searchParams.get("u"), p_token: url.searchParams.get("t") ?? "",
    });
    // Supabase не показывает HTML-страницы из функций — отправляем человека на сайт, там сообщение
    const site = (await setting("site_url")) || "https://zumihome.com";
    return Response.redirect(`${site}/?email_alerts=${data === true ? "off" : "bad"}`, 302);
  }

  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const secret = await setting("email_cron_secret");
  if (!secret || req.headers.get("x-cron-secret") !== secret) return new Response("Forbidden", { status: 403 });
  if (!RESEND_KEY && (!SMTP_USER || !SMTP_PASS)) {
    console.warn("email-notify: SMTP_USER / SMTP_PASS not set");
    return new Response("not configured");
  }

  const { data, error } = await db.rpc("email_due", { p_limit: 40 });
  if (error) {
    console.error("email_due failed", error.message);
    return new Response("error", { status: 500 });
  }
  const items = (data ?? []) as Item[];
  if (items.length === 0) return new Response("nothing to send");
  const site = (await setting("site_url")) || "https://zumihome.com";
  const res = await sendAll(items, site);
  console.log("email-notify", res);
  return new Response(JSON.stringify(res), { headers: { "Content-Type": "application/json" } });
});
