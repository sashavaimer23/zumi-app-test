// Zumi — подтверждение оплаты от платёжного провайдера (заготовка, пока НЕ развёрнута).
// Когда будет компания и договор с провайдером Mobile Money (MTN MoMo, Airtel Money или агрегатор),
// провайдер присылает сюда уведомление об успешной оплате → mark_order_paid() → услуга включается сама.
//
// Что останется сделать при подключении:
//   1. Supabase → Edge Functions → создать функцию payment-webhook с этим кодом, «Verify JWT» выключить.
//   2. Secrets: PAYMENT_WEBHOOK_SECRET — общий секрет с провайдером (или проверка подписи по его документации).
//   3. В кабинете провайдера указать адрес: https://<project>.supabase.co/functions/v1/payment-webhook
//   4. Поправить разбор тела запроса под формат провайдера (функция parse ниже).
//   5. Supabase SQL: update app_settings set value = 'auto' where key = 'payment_mode';
//
// Код заказа (Z-XXXXXX) передаётся провайдеру как «reference» при создании платежа.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SECRET = (Deno.env.get("PAYMENT_WEBHOOK_SECRET") ?? "").trim();
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// формат у каждого провайдера свой — здесь общий пример
function parse(body: any): { ref: string; ok: boolean; provider: string; providerRef: string } | null {
  const ref = body?.reference ?? body?.externalId ?? body?.tx_ref;
  if (!ref) return null;
  const status = String(body?.status ?? "").toUpperCase();
  return {
    ref: String(ref),
    ok: ["SUCCESSFUL", "SUCCESS", "COMPLETED", "PAID"].includes(status),
    provider: String(body?.provider ?? "mobile_money"),
    providerRef: String(body?.transactionId ?? body?.financialTransactionId ?? body?.id ?? ""),
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!SECRET || req.headers.get("x-zumi-secret") !== SECRET) {
    console.warn("payment-webhook: bad secret");
    return new Response("Forbidden", { status: 403 });
  }
  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  const p = parse(body);
  if (!p) return new Response("No reference", { status: 400 });
  if (!p.ok) {
    console.log("payment-webhook: not successful", { ref: p.ref, status: body?.status });
    return new Response("ok");
  }
  const { data, error } = await db.rpc("mark_order_paid", {
    p_ref: p.ref, p_provider: p.provider, p_provider_ref: p.providerRef,
  });
  if (error) {
    console.error("mark_order_paid failed", error.message);
    return new Response("Error", { status: 500 }); // провайдер повторит позже
  }
  console.log("payment-webhook: order", { ref: p.ref, result: data });
  return new Response("ok");
});
