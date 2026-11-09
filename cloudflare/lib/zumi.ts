// Общие функции для страниц Cloudflare Pages: данные из Supabase и HTML.
// Эти страницы видят Google и WhatsApp/Facebook (превью ссылки); людей с объявления перекидываем в приложение.
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./config";

export const SITE = "https://zumihome.com";

export type Listing = {
  id: string; title: string; description: string | null; deal_type: string; property_type: string;
  price: number; currency: string | null; rent_period: string | null; bedrooms: number | null;
  bathrooms: number | null; area_sqm: number | null; area_name: string | null; city: string | null;
  image_urls: string[] | null; thumb_urls: string[] | null; listed_by: string | null; agency_name: string | null;
  owner_name: string | null; owner_id: string | null; created_at: string; units_total: number | null;
  units_available: number | null; is_fresh: boolean; status: string;
};

export const LISTING_COLS =
  "id,title,description,deal_type,property_type,price,currency,rent_period,bedrooms,bathrooms,area_sqm," +
  "area_name,city,image_urls,thumb_urls,listed_by,agency_name,owner_name,owner_id,created_at,units_total," +
  "units_available,is_fresh,status";

export async function sb<T>(path: string, init?: RequestInit): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    cf: { cacheTtl: 300, cacheEverything: true },
  } as RequestInit);
  if (!r.ok) throw new Error(`supabase ${r.status}`);
  return (await r.json()) as T;
}

export const rpc = <T>(name: string, args: Record<string, unknown>) =>
  sb<T>(`rpc/${name}`, { method: "POST", body: JSON.stringify(args) });

// кто пришёл: поисковик / мессенджер (показываем страницу) или человек (в приложение)
const BOTS = /bot|crawl|spider|slurp|facebookexternalhit|facebot|whatsapp|telegram|twitter|slack|linkedin|discord|viber|skype|pinterest|embedly|preview|google|bing|yandex|applebot|duckduck/i;
// ?preview — посмотреть страницу так, как её видят Google и WhatsApp
export const isBot = (req: Request) =>
  BOTS.test(req.headers.get("user-agent") ?? "") || new URL(req.url).searchParams.has("preview");

// демо-фото хранятся в приложении («asset:p1.jpg») — даём полный адрес
export const img = (u?: string | null) =>
  !u ? undefined : u.startsWith("asset:") ? `${SITE}/assets/assets/images/${u.slice(6)}` : u;

export const esc = (s: unknown) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export const slug = (s: string) => s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

export function money(n: number, cur?: string | null) {
  const v = Math.round(n).toLocaleString("en-US");
  return !cur || cur === "ZMW" ? `K${v}` : `${cur} ${v}`;
}

const TYPES: Record<string, [string, string]> = {
  house: ["house", "houses"], apartment: ["flat", "flats"], land: ["plot", "plots"],
  commercial: ["commercial property", "commercial properties"], room: ["room", "rooms"],
};
export const typeName = (t: string, plural = false) => (TYPES[t] ?? [t, `${t}s`])[plural ? 1 : 0];

export function priceLine(p: Listing) {
  const per = p.deal_type === "rent" ? (p.rent_period === "day" ? " / day" : " / month") : "";
  return `${money(p.price, p.currency)}${per}`;
}

export function specs(p: Listing) {
  const a: string[] = [];
  if (p.bedrooms) a.push(`${p.bedrooms} bed`);
  if (p.bathrooms) a.push(`${p.bathrooms} bath`);
  if (p.area_sqm) a.push(`${Math.round(p.area_sqm)} m²`);
  if (p.units_total && p.units_total > 1) a.push(`${p.units_available ?? 1} of ${p.units_total} units free`);
  return a.join(" · ");
}

export function headline(p: Listing) {
  const beds = p.bedrooms ? `${p.bedrooms}-bedroom ` : "";
  const deal = p.deal_type === "rent" ? "for rent" : "for sale";
  return `${beds}${typeName(p.property_type)} ${deal} in ${p.area_name ?? p.city ?? "Zambia"}`;
}

export function page(o: {
  title: string; description: string; url: string; image?: string | null; body: string; noindex?: boolean;
  jsonld?: unknown;
}) {
  const image = img(o.image) || `${SITE}/og-image.jpg`;
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(o.title)}</title>
<meta name="description" content="${esc(o.description)}">
<link rel="canonical" href="${esc(o.url)}">
${o.noindex ? '<meta name="robots" content="noindex">' : ""}
<meta property="og:type" content="website"><meta property="og:site_name" content="Zumi">
<meta property="og:url" content="${esc(o.url)}"><meta property="og:title" content="${esc(o.title)}">
<meta property="og:description" content="${esc(o.description)}"><meta property="og:image" content="${esc(image)}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="${esc(image)}">
<link rel="icon" type="image/png" href="/favicon.png">
${o.jsonld ? `<script type="application/ld+json">${JSON.stringify(o.jsonld).replace(/</g, "\\u003c")}</script>` : ""}
<style>
body{margin:0;background:#FBF7F2;color:#1F2A26;font:16px/1.55 -apple-system,Segoe UI,Roboto,Arial,sans-serif}
main{max-width:980px;margin:0 auto;padding:18px 16px 60px}
a{color:#C9583A}header{display:flex;justify-content:space-between;align-items:center;padding:6px 0 14px}
.logo{color:#245045;font-weight:800;letter-spacing:3px;text-decoration:none;font-size:22px}
.btn{display:inline-block;background:#F07A5A;color:#fff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:24px}
h1{color:#245045;font-size:30px;line-height:1.2;margin:8px 0 6px}h2{color:#245045;font-size:20px;margin:28px 0 10px}
.muted{color:#6E7A74}.price{color:#245045;font-weight:800;font-size:24px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px}
.card{background:#fff;border-radius:18px;overflow:hidden;text-decoration:none;color:inherit;display:block}
.card img{width:100%;height:180px;object-fit:cover;background:#EDE7DF;display:block}
.card div{padding:12px 14px}.card b{color:#245045;font-size:18px}
.hero{width:100%;max-height:460px;object-fit:cover;border-radius:18px;background:#EDE7DF}
.chips a{display:inline-block;background:#E8EFEA;color:#245045;text-decoration:none;padding:6px 12px;border-radius:14px;margin:0 6px 8px 0;font-size:14px}
footer{margin-top:40px;font-size:14px}
</style></head><body><main>
<header><a class="logo" href="/">ZUMI</a><a class="btn" href="/">Open Zumi</a></header>
${o.body}
<footer class="muted"><a href="/">Zumi</a> — homes to rent and buy in Zambia · <a href="/agents">For agents</a> · <a href="/terms.html">Terms</a> · <a href="/privacy.html">Privacy</a></footer>
</main></body></html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300" } },
  );
}

export function card(p: Listing) {
  const pic = img(p.thumb_urls?.[0] ?? p.image_urls?.[0]);
  return `<a class="card" href="/l/${p.id}">${pic ? `<img src="${esc(pic)}" alt="${esc(headline(p))}" loading="lazy">` : "<img alt=''>"}
<div><b>${esc(priceLine(p))}</b><br>${esc(p.title)}<br><span class="muted">${esc(specs(p))}${p.area_name ? ` · ${esc(p.area_name)}` : ""}</span></div></a>`;
}

export const notFound = () =>
  page({ title: "Not found — Zumi", description: "This page is not available.", url: SITE, noindex: true,
    body: `<h1>This listing is no longer available</h1><p><a class="btn" href="/">See homes on Zumi</a></p>` });
