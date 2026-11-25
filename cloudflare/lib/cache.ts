// Кэш лёгких страниц на серверах Cloudflare (рядом с человеком, в т.ч. в Африке).
// 1 000 человек открыли одно объявление — база получает 1 запрос, а не 1 000.
// Страница обновляется не реже чем раз в `ttl` секунд.
declare const caches: { default: Cache };

export async function edgeCached(request: Request, ttl: number, make: () => Promise<Response>): Promise<Response> {
  if (request.method !== "GET") return make();
  let cache: Cache | null = null;
  try {
    cache = caches.default;
  } catch {
    cache = null; // локальная проверка без Cloudflare
  }
  const key = new Request(new URL(request.url).toString(), { method: "GET" });
  if (cache) {
    const hit = await cache.match(key).catch(() => undefined);
    if (hit) return hit;
  }
  const res = await make();
  // кэшируем только нормальные страницы (не редиректы и не «не найдено»)
  if (cache && res.status === 200) {
    const copy = new Response(res.clone().body, res);
    copy.headers.set("Cache-Control", `public, max-age=${ttl}`);
    await cache.put(key, copy).catch(() => null);
  }
  return res;
}
