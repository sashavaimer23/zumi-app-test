// /l/<id>?c=<адрес каталога> — объект из каталога агента: лёгкая страница с фото, деталями и WhatsApp агента.
import { AMENITY, avatar, badges, contactBar, DEMO_SLUG, isDemo, isSlug, ITEM_COLS, Item, loadCatalog, shareScript, shell } from "./catalog";
import { esc, headline, img, priceLine, sb, SITE, specs } from "./zumi";

export async function catalogItem(id: string, slug: string): Promise<Response | null> {
  if (!isSlug(slug) && slug !== DEMO_SLUG) return null;
  const [c, rows] = await Promise.all([
    loadCatalog(slug),
    sb<Item[]>(`property_feed?select=${ITEM_COLS}&id=eq.${id}&status=eq.active&limit=1`).catch(() => [] as Item[]),
  ]);
  const p = rows[0];
  if (!c || !p || (isDemo(c) ? p.owner_id : p.owner_id !== c.id)) return null;

  const url = `${SITE}/l/${id}?c=${slug}`;
  const h = headline(p);
  const pics = (p.image_urls ?? []).map((u) => img(u)).filter(Boolean) as string[];
  const first = c.name.split(/\s+/)[0] || c.name;
  const facts = [
    p.bedrooms ? `${p.bedrooms} bedrooms` : "", p.bathrooms ? `${p.bathrooms} bathrooms` : "",
    p.area_sqm ? `${Math.round(p.area_sqm)} m²` : "", p.area_name ?? "",
    p.advance_months && p.deal_type === "rent" ? `${p.advance_months} ${p.advance_months === 1 ? "month" : "months"} upfront` : "",
    p.units_total && p.units_total > 1 ? `${p.units_available ?? 1} of ${p.units_total} units free` : "",
  ].filter(Boolean);
  const am = (p.amenities ?? []).map((a) => AMENITY[a]).filter(Boolean);

  const body = `<div class="wrap">
<a class="back" href="/${slug}">← ${esc(c.name)}'s catalogue</a>
${pics.length ? `<div class="gal">${pics.map((u, i) => `<img src="${esc(u)}" alt="${esc(h)}" ${i ? 'loading="lazy"' : 'fetchpriority="high"'} decoding="async">`).join("")}</div>
${pics.length > 1 ? `<div class="mut" style="margin-top:6px">${pics.length} photos — swipe to see all</div>` : ""}` : ""}
<div class="price">${esc(priceLine(p))}</div>
<h1 style="color:#245045;font-size:22px;margin:4px 0">${esc(p.title)}</h1>
<div class="mut">${esc(h)}</div>
${facts.length ? `<div class="facts" style="margin-top:12px">${facts.map((f) => `<span>${esc(f)}</span>`).join("")}</div>` : ""}
${p.description ? `<h2>About</h2><p style="margin:0">${esc(p.description).replace(/\n/g, "<br>")}</p>` : ""}
${am.length ? `<h2>Power, water and amenities</h2><div class="facts">${am.map((a) => `<span>${esc(a)}</span>`).join("")}</div>` : ""}
<a class="agent" href="/${slug}">${avatar(c)}<div><b>${esc(c.name)}</b><div class="mut">${c.agency_name ? esc(c.agency_name) + " · " : ""}See all properties</div>
<div style="margin-top:4px">${badges(c).replace(/class="bdg"/g, 'class="mut" style="margin-right:8px"')}</div></div></a>
<div class="safe">Never pay a deposit or viewing fee before you have seen the property in person.</div>
<div class="foot"><a href="${SITE}/?listing=${id}">Open in the Zumi app</a> · <a data-share href="${esc(`https://wa.me/?text=${encodeURIComponent(`${p.title} — ${priceLine(p)}\n${url}`)}`)}">Share</a></div>
</div>${shareScript(url, p.title)}`;

  return shell({
    title: `${priceLine(p)} · ${h}`,
    description: [specs(p), `Listed by ${c.name}${c.agency_name ? ` (${c.agency_name})` : ""}`].filter(Boolean).join(" · "),
    url, image: pics[0], body,
    bar: contactBar(c, `Hi ${first}, I'm interested in "${p.title}" (${priceLine(p)}) from your Zumi catalogue: ${url}`),
  });
}
