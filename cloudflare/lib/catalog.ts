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
  "pricing plans contact news jobs careers legal security status test staging example demo").split(" "));
export const isSlug = (s: string) =>
  /^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/.test(s) && !s.includes("--") && !RESERVED.has(s) && !/^(rent|buy)-/.test(s);

// zumihome.com/example — образец каталога на демо-объявлениях (посмотреть, как это выглядит)
export const DEMO_SLUG = "example";
const DEMO: Catalog = {
  id: "demo", slug: DEMO_SLUG, role: "agent", name: "Example Agent", agency_name: "Sample Realty",
  agency_id: null, avatar_url: null,
  bio: "This is an example of a Zumi catalogue. Your catalogue shows your photo, a few words about you, " +
    "the areas you cover and all your properties — share one link with clients instead of sending listings one by one.",
  areas: "Ibex Hill, Woodlands, Kabulonga", licensed: true, phone_checked: true, since: "2026", contact: null,
};
export const isDemo = (c: Catalog) => c.id === "demo";

export async function loadCatalog(slug: string): Promise<Catalog | null> {
  if (slug === DEMO_SLUG) return DEMO;
  const c = await rpc<Catalog | null>("catalog_page", { p_slug: slug }).catch(() => null);
  return c && c.id ? c : null;
}

export const loadItems = (ownerId: string) =>
  sb<Item[]>(`property_feed?select=${ITEM_COLS}&${ownerId === "demo" ? "is_demo=eq.true" : `owner_id=eq.${ownerId}&is_fresh=eq.true`}&status=eq.active&order=created_at.desc&limit=${ownerId === "demo" ? 12 : 80}`)
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
.top{background:linear-gradient(135deg,#1E4A3F 0%,#2F6B5B 60%,#3E7A68 100%);color:#fff;padding:14px 0 118px}
.top .bar{display:flex;justify-content:space-between;align-items:center}
.logo{color:#fff;font-weight:800;letter-spacing:4px;text-decoration:none;font-size:17px;opacity:.92}
.share{background:rgba(255,255,255,.14);color:#fff;border:1px solid rgba(255,255,255,.25);border-radius:20px;padding:7px 16px;font-family:inherit;font-weight:600;font-size:14px;cursor:pointer;text-decoration:none}
.prof{position:relative;background:#fff;border-radius:26px;margin-top:-62px;padding:0 22px 26px;text-align:center;box-shadow:0 6px 24px rgba(30,74,63,.08)}
.prof .av{margin:0 auto;transform:translateY(-50%);margin-bottom:-38px}
.av{width:104px;height:104px;border-radius:50%;object-fit:cover;background:#F07A5A;color:#fff;font-weight:700;font-size:36px;letter-spacing:1px;display:flex;align-items:center;justify-content:center;flex:none;border:5px solid #fff;box-shadow:0 4px 14px rgba(0,0,0,.08)}
.prof h1{margin:0;color:#1E4A3F;font-size:26px;line-height:1.2;letter-spacing:-.2px}
.prof .ag{color:#6E7A74;font-size:15px;margin-top:3px}
.bdgs{margin-top:14px;display:flex;flex-wrap:wrap;gap:8px;justify-content:center}
.bdg{background:#E8F3EC;color:#1F7A4A;border-radius:16px;padding:5px 12px;font-size:13px;font-weight:600}
.stats{display:flex;justify-content:center;margin:20px auto 0;max-width:460px;border-top:1px solid #F0EBE4;border-bottom:1px solid #F0EBE4}
.stats div{flex:1;padding:12px 6px}.stats div+div{border-left:1px solid #F0EBE4}
.stats b{display:block;color:#1E4A3F;font-size:20px;line-height:1.2}.stats span{color:#6E7A74;font-size:12.5px}
.areas{margin-top:16px;color:#245045;font-size:14.5px;font-weight:600}
.areas small{display:block;color:#9AA49F;font-weight:500;font-size:11.5px;letter-spacing:1px;text-transform:uppercase;margin-bottom:2px}
.bio{margin:12px auto 0;font-size:15px;color:#4A5651;max-width:560px;line-height:1.6}
.sec{display:flex;align-items:baseline;justify-content:space-between;margin:34px 0 14px}
.sec h2{margin:0;color:#1E4A3F;font-size:22px}.sec h2 span{color:#9AA49F;font-weight:500;font-size:18px;margin-left:6px}
.filters{display:flex;flex-wrap:wrap;gap:12px 18px;align-items:center;justify-content:space-between;margin-bottom:20px}
.seg{display:inline-flex;background:#EFE9E1;border-radius:22px;padding:4px}
.seg button{border:0;background:none;color:#4A5651;border-radius:18px;padding:8px 16px;font-family:inherit;font-weight:600;font-size:14px;cursor:pointer;white-space:nowrap}
.seg button.on{background:#fff;color:#1E4A3F;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.types{display:flex;gap:8px;overflow-x:auto;scrollbar-width:none;max-width:100%}
.types button{flex:none;border:1px solid #E2DBD1;background:transparent;color:#4A5651;border-radius:18px;padding:7px 14px;font-family:inherit;font-weight:500;font-size:13.5px;cursor:pointer}
.types button.on{background:#1E4A3F;border-color:#1E4A3F;color:#fff}
.note{text-align:center;color:#8A7A55;font-size:13px;margin:14px 0 0}.note a{color:#8A7A55}
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
.cta .wrap{display:flex;gap:10px;padding:0;max-width:560px}
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
.agent .av{width:52px;height:52px;font-size:20px;border:0;box-shadow:none}
.safe{background:#FFF1D6;color:#6B4A00;border-radius:14px;padding:10px 14px;font-size:13.5px;margin-top:18px}
@media(min-width:760px){.prof h1{font-size:32px}.prof{padding:0 40px 32px}.top{padding-bottom:132px}.prof .av{width:120px;height:120px;margin-bottom:-44px}}
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
  if (isDemo(c)) return `<div class="cta"><div class="wrap"><a class="app" href="/agents">Example — make your own free catalogue</a></div></div>`;
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
