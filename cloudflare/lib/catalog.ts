// Каталог агента (портфолио): zumihome.com/<адрес> и объект из каталога /l/<id>?c=<адрес>.
// Лёгкие страницы для ВСЕХ (не только для Google): ~100–150 КБ на первый экран, фото грузятся по мере прокрутки.
import { esc, img, LISTING_COLS, Listing, money, priceLine, rpc, sb, SITE, specs, typeName } from "./zumi";

export type Catalog = {
  id: string; slug: string; role: string; name: string; agency_name: string | null; agency_id: string | null;
  avatar_url: string | null; bio: string | null; areas: string | null; licensed: boolean; phone_checked: boolean;
  since: string | null; contact: string | null;
};

export type Item = Listing & { amenities: string[] | null; advance_months: number | null };
export const ITEM_COLS = `${LISTING_COLS},amenities,advance_months`;

// адреса, которые заняты сайтом (как _slug_reserved в базе)
const RESERVED = new Set(("agents agent agency agencies l rent buy terms privacy delete-account sitemap admin api " +
  "assets icons canvaskit help support login signup sign-up register zumi about blog app settings search map post www " +
  "mail hello team owner owners catalog catalogue listing listings home index robots favicon manifest join invite " +
  "pricing plans contact news jobs careers legal security status test staging").split(" "));
export const isSlug = (s: string) =>
  /^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/.test(s) && !s.includes("--") && !RESERVED.has(s) && !/^(rent|buy)-/.test(s);

export async function loadCatalog(slug: string): Promise<Catalog | null> {
  const c = await rpc<Catalog | null>("catalog_page", { p_slug: slug }).catch(() => null);
  return c && c.id ? c : null;
}

export const loadItems = (ownerId: string) =>
  sb<Item[]>(`property_feed?select=${ITEM_COLS}&owner_id=eq.${ownerId}&status=eq.active&is_fresh=eq.true&order=created_at.desc&limit=80`)
    .catch(() => [] as Item[]);

const POWER: Record<string, string> = {
  solar: "Solar", inverter: "Inverter", generator: "Generator", borehole: "Borehole", water_tank: "Water tank",
  water_24h: "Water 24/7", prepaid_meter: "Prepaid meter", council_water: "Council water",
};
export const AMENITY: Record<string, string> = {
  ...POWER, parking: "Parking", furnished: "Furnished", garden: "Garden", pool: "Swimming pool",
  ac: "Air conditioning", internet: "Internet", tv: "TV",
  fridge: "Fridge", washing_machine: "Washing machine", dishwasher: "Dishwasher", garage: "Garage",
};
const powerTags = (p: Item) => (p.amenities ?? []).filter((a) => POWER[a]).slice(0, 3).map((a) => POWER[a]);

export const initials = (s: string) => s.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join("");
export const wa = (num: string, text: string) => `https://wa.me/${num}?text=${encodeURIComponent(text)}`;

// значки доверия
export function badges(c: Catalog) {
  const b: string[] = [];
  if (c.phone_checked) b.push(`<span class="bdg">✓ Number checked</span>`);
  if (c.licensed) b.push(`<span class="bdg">✓ Licensed agent (ZIEA)</span>`);
  return b.join("");
}

// общий вид страниц каталога
export function shell(o: { title: string; description: string; url: string; image?: string | null; body: string; bar?: string }) {
  const image = img(o.image) || `${SITE}/og-image.jpg`;
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(o.title)}</title><meta name="description" content="${esc(o.description)}">
<link rel="canonical" href="${esc(o.url)}">
<meta property="og:type" content="profile"><meta property="og:site_name" content="Zumi">
<meta property="og:url" content="${esc(o.url)}"><meta property="og:title" content="${esc(o.title)}">
<meta property="og:description" content="${esc(o.description)}"><meta property="og:image" content="${esc(image)}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="${esc(image)}">
<meta name="theme-color" content="#245045"><link rel="icon" type="image/png" href="/favicon.png">
<style>
*{box-sizing:border-box}
body{margin:0;background:#FBF7F2;color:#1F2A26;font:16px/1.5 -apple-system,Segoe UI,Roboto,Arial,sans-serif;padding-bottom:84px}
a{color:#C9583A}
.wrap{max-width:980px;margin:0 auto;padding:0 16px}
.top{background:linear-gradient(160deg,#245045,#2F5F52);color:#fff;padding:14px 0 26px}
.top .bar{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
.logo{color:#fff;font-weight:800;letter-spacing:3px;text-decoration:none;font-size:18px;opacity:.9}
.share{background:rgba(255,255,255,.15);color:#fff;border:0;border-radius:20px;padding:8px 14px;font-family:inherit;font-weight:600;font-size:14px;cursor:pointer;text-decoration:none}
.who{display:flex;gap:16px;align-items:center}
.av{width:76px;height:76px;border-radius:50%;object-fit:cover;background:#F07A5A;color:#fff;font-weight:700;font-size:28px;display:flex;align-items:center;justify-content:center;flex:none;border:3px solid rgba(255,255,255,.85)}
.who h1{margin:0;font-size:25px;line-height:1.2}
.who .ag{opacity:.85;font-size:15px}
.bdgs{margin-top:12px;display:flex;flex-wrap:wrap;gap:6px}
.bdg{background:rgba(255,255,255,.16);border-radius:14px;padding:4px 10px;font-size:13px}
.meta{margin-top:12px;font-size:14px;opacity:.85}
.bio{margin:14px 0 0;font-size:15px;opacity:.95;max-width:640px}
.tabs{display:flex;gap:8px;overflow-x:auto;padding:18px 0 4px;scrollbar-width:none}
.tabs button{flex:none;border:1px solid #D9D2C8;background:#fff;color:#245045;border-radius:20px;padding:8px 16px;font-family:inherit;font-weight:600;font-size:14px;cursor:pointer}
.tabs button.on{background:#245045;border-color:#245045;color:#fff}
.count{color:#6E7A74;font-size:14px;margin:8px 0 12px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:14px}
.card{background:#fff;border-radius:18px;overflow:hidden;text-decoration:none;color:inherit;display:block;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.card .ph{position:relative;aspect-ratio:4/3;background:#EDE7DF}
.card img{width:100%;height:100%;object-fit:cover;display:block}
.card .deal{position:absolute;left:10px;top:10px;background:#fff;color:#245045;font-weight:700;font-size:12px;padding:3px 9px;border-radius:10px}
.card .n{position:absolute;right:10px;bottom:10px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;padding:2px 8px;border-radius:10px}
.card .tx{padding:11px 13px 13px}
.card b{color:#245045;font-size:18px}
.card .t{margin:2px 0;font-size:15px}
.mut{color:#6E7A74;font-size:13.5px}
.tags{margin-top:6px;display:flex;flex-wrap:wrap;gap:5px}
.tags span{background:#E8EFEA;color:#245045;font-size:12px;padding:2px 8px;border-radius:10px}
.empty{background:#fff;border-radius:18px;padding:28px;text-align:center;color:#6E7A74}
.cta{position:fixed;left:0;right:0;bottom:0;background:#fff;box-shadow:0 -2px 12px rgba(0,0,0,.08);padding:10px 16px calc(10px + env(safe-area-inset-bottom))}
.cta .wrap{display:flex;gap:10px;padding:0}
.cta a{flex:1;text-align:center;text-decoration:none;font-weight:700;border-radius:24px;padding:13px 10px}
.wa{background:#1FAF5A;color:#fff}.call{background:#fff;color:#245045;border:2px solid #245045}.app{background:#F07A5A;color:#fff}
.foot{margin:34px 0 10px;text-align:center;font-size:13.5px;color:#6E7A74}
.foot a{color:#245045}
.made{display:inline-block;margin-top:8px;background:#fff;border-radius:16px;padding:10px 16px;text-decoration:none;color:#245045;font-weight:600}
/* объект */
.gal{display:flex;gap:8px;overflow-x:auto;scroll-snap-type:x mandatory;border-radius:18px;margin-top:14px;scrollbar-width:none}
.gal img{flex:none;width:100%;max-width:720px;aspect-ratio:4/3;object-fit:cover;scroll-snap-align:start;border-radius:18px;background:#EDE7DF}
.price{color:#245045;font-weight:800;font-size:26px;margin:14px 0 0}
h2{color:#245045;font-size:18px;margin:22px 0 8px}
.facts{display:flex;flex-wrap:wrap;gap:8px}.facts span{background:#fff;border-radius:12px;padding:6px 12px;font-size:14px}
.back{display:inline-block;margin:12px 0 0;text-decoration:none;color:#245045;font-weight:600}
.agent{display:flex;gap:12px;align-items:center;background:#fff;border-radius:18px;padding:12px 14px;text-decoration:none;color:inherit;margin-top:22px}
.agent .av{width:52px;height:52px;font-size:20px;border:0}
.safe{background:#FFF1D6;color:#6B4A00;border-radius:14px;padding:10px 14px;font-size:13.5px;margin-top:18px}
@media(min-width:760px){.who h1{font-size:30px}.who .av{width:92px;height:92px}}
@media(max-width:560px){.grid{grid-template-columns:1fr 1fr;gap:10px}.card{border-radius:14px}.card b{font-size:15px}.card .t{font-size:13.5px;line-height:1.3}.card .tx{padding:8px 10px 10px}.card .deal{font-size:11px;left:7px;top:7px;padding:2px 7px}.card .n{display:none}.mut{font-size:12.5px}.tags span{font-size:11px;padding:1px 6px}}
</style></head><body>${o.body}${o.bar ?? ""}</body></html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=120" } });
}

export function avatar(c: Catalog) {
  const a = img(c.avatar_url);
  return a ? `<img class="av" src="${esc(a)}" alt="${esc(c.name)}">` : `<div class="av">${esc(initials(c.name) || "Z")}</div>`;
}

export function itemCard(p: Item, slug: string) {
  const pic = img(p.thumb_urls?.[0] ?? p.image_urls?.[0]);
  const n = p.image_urls?.length ?? 0;
  const tags = powerTags(p);
  return `<a class="card" href="/l/${p.id}?c=${slug}" data-deal="${p.deal_type}" data-type="${p.property_type}">
<div class="ph">${pic ? `<img src="${esc(pic)}" alt="" loading="lazy" decoding="async">` : ""}
<span class="deal">${p.deal_type === "rent" ? "For rent" : "For sale"}</span>${n > 1 ? `<span class="n">${n} photos</span>` : ""}</div>
<div class="tx"><b>${esc(priceLine(p))}</b><div class="t">${esc(p.title)}</div>
<div class="mut">${esc([specs(p), p.area_name].filter(Boolean).join(" · "))}</div>
${tags.length ? `<div class="tags">${tags.map((t) => `<span>${esc(t)}</span>`).join("")}</div>` : ""}</div></a>`;
}

export function contactBar(c: Catalog, text: string) {
  const app = `${SITE}/?agent=${c.id}`;
  return c.contact
    ? `<div class="cta"><div class="wrap"><a class="wa" href="${esc(wa(c.contact, text))}">WhatsApp</a><a class="call" href="tel:+${esc(c.contact)}">Call</a></div></div>`
    : `<div class="cta"><div class="wrap"><a class="app" href="${esc(app)}">Contact on Zumi</a></div></div>`;
}

export const shareScript = (url: string, title: string) => `<script>
document.querySelectorAll('[data-share]').forEach(function(b){b.addEventListener('click',function(e){
var u=${JSON.stringify(url)},t=${JSON.stringify(title)};
if(navigator.share){e.preventDefault();navigator.share({title:t,url:u}).catch(function(){});}
});});
</script>`;

export { money, typeName };
