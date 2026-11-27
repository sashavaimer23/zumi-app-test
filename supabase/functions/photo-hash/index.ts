// Zumi — «отпечатки» фото объявлений (защита от мошенников, миграция 042).
// Раз в 5 минут база (pg_cron) зовёт эту функцию → берём фото без отпечатка → скачиваем →
// считаем dHash (64 бита: одинаковые фото дают одинаковый или очень похожий отпечаток, даже если
// их пережали или чуть обрезали) и sha256 → сохраняем. Дальше база сама сравнивает объявления.
//
// Как создать (один раз): Supabase → Edge Functions → Deploy a new function → «Via Editor»,
// имя photo-hash, вставить этот код, Deploy. В настройках функции «Verify JWT» — ВЫКЛЮЧИТЬ.
// Секреты не нужны (использует тот же email_cron_secret, что и письма).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { decode, Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function setting(key: string): Promise<string> {
  const { data } = await db.from("app_settings").select("value").eq("key", key).maybeSingle();
  return (data?.value as string) ?? "";
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("");
}

// dHash: уменьшаем до 9×8 в оттенках серого и сравниваем соседние пиксели слева направо
function dHash(img: Image): string {
  const small = img.resize(9, 8);
  let bits = "";
  for (let y = 1; y <= 8; y++) {
    for (let x = 1; x <= 8; x++) {
      const a = Image.colorToRGBA(small.getPixelAt(x, y));
      const b = Image.colorToRGBA(small.getPixelAt(x + 1, y));
      const ga = a[0] * 0.299 + a[1] * 0.587 + a[2] * 0.114;
      const gb = b[0] * 0.299 + b[1] * 0.587 + b[2] * 0.114;
      bits += ga > gb ? "1" : "0";
    }
  }
  return bits;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const secret = await setting("email_cron_secret");
  if (!secret || req.headers.get("x-cron-secret") !== secret) return new Response("Forbidden", { status: 403 });

  const { data, error } = await db.rpc("photos_to_hash", { p_limit: 30 });
  if (error) return new Response("error: " + error.message, { status: 500 });
  const rows = (data ?? []) as { id: string; url: string }[];
  let ok = 0, failed = 0;
  for (const r of rows) {
    try {
      const res = await fetch(r.url);
      if (!res.ok) throw new Error(`download ${res.status}`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (bytes.length > 15_000_000) throw new Error("too big");
      const img = await decode(bytes);
      if (!(img instanceof Image)) throw new Error("not a still image");
      await db.rpc("photo_hashed", { p_id: r.id, p_phash: dHash(img), p_sha256: await sha256(bytes), p_error: null });
      ok++;
    } catch (e) {
      failed++;
      // отмечаем, чтобы не пытаться бесконечно; без отпечатка фото просто не участвует в сравнении
      await db.rpc("photo_hashed", { p_id: r.id, p_phash: null, p_sha256: null, p_error: String(e) });
    }
  }
  return new Response(JSON.stringify({ ok, failed, left: rows.length === 30 ? "more" : 0 }),
    { headers: { "Content-Type": "application/json" } });
});
