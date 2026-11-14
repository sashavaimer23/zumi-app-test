// Лёгкая страница объявления для ВСЕХ: zumihome.com/l/<id>  (и /l/<id>?c=<каталог> — из каталога агента).
// ~100 КБ: фото листаются, детали, связь. Тяжёлый сайт грузится, только если человек нажмёт «See more homes».
import { AMENITY, avatar, badges, Catalog, contactBar, DEMO_SLUG, isDemo, isSlug, ITEM_COLS, Item, itemCard, loadCatalog, shareScript, shell } from "./catalog";
import { esc, headline, img, priceLine, rpc, sb, SITE, slug as slugify, specs, typeName } from "./zumi";

const loadItem = (id: string) =>
  sb<Item[]>(`property_feed?select=${ITEM_COLS}&id=eq.${id}&status=eq.active&limit=1`).then((r) => r[0] ?? null).catch(() => null);

const ownerCard = (ownerId: string | null) =>
  ownerId ? rpc<Catalog | null>("owner_card", { p_owner: ownerId }).then((c) => (c && c.id ? c : null)).catch(() => null) : Promise.resolve(null);

/** Страница объекта из каталога агента: /l/<id>?c=<адрес> */
export async function catalogItem(id: string, slug: string): Promise<Response | null> {
  if (!isSlug(slug) && slug !== DEMO_SLUG) return null;
  const [c, p] = await Promise.all([loadCatalog(slug), loadItem(id)]);
  if (!c || !p || (isDemo(c) ? p.owner_id : p.owner_id !== c.id)) return null;
  return render(p, c, slug, [], true);
}

/** Обычная страница объекта: /l/<id> — для людей, Google и WhatsApp */
export async function listingPage(id: string): Promise<Response | null> {
  const p = await loadItem(id);
  if (!p) return null;
  const [c, more] = await Promise.all([
    ownerCard(p.owner_id),
    p.area_name
      ? sb<Item[]>(`property_feed?select=${ITEM_COLS}&status=eq.active&is_fresh=eq.true&area_name=eq.${encodeURIComponent(p.area_name)}&deal_type=eq.${p.deal_type}&id=neq.${id}&order=created_at.desc&limit=6`).catch(() => [] as Item[])
      : Promise.resolve([] as Item[]),
  ]);
  return render(p, c, c?.slug ?? null, more, false);
}

function render(p: Item, c: Catalog | null, catSlug: string | null, more: Item[], viaCatalog: boolean): Response {
  const id = p.id;
  const fromCatalog = viaCatalog && !!catSlug && !!c && (isDemo(c) || c.slug === catSlug);
  const url = fromCatalog && catSlug ? `${SITE}/l/${id}?c=${catSlug}` : `${SITE}/l/${id}`;
  const canonical = `${SITE}/l/${id}`;
  const app = `${SITE}/?listing=${id}`;
  const h = headline(p);
  const pics = (p.image_urls ?? []).map((u) => img(u)).filter(Boolean) as string[];
  const name = c?.name ?? (p.listed_by === "agent" ? (p.agency_name || p.owner_name || "Agent") : "Owner");
  const first = name.split(/\s+/)[0] || name;
  const deal = p.deal_type === "rent" ? "rent" : "buy";
  const facts = [
    p.bedrooms ? `${p.bedrooms} ${p.bedrooms === 1 ? "bedroom" : "bedrooms"}` : "",
    p.bathrooms ? `${p.bathrooms} ${p.bathrooms === 1 ? "bathroom" : "bathrooms"}` : "",
    p.area_sqm ? `${Math.round(p.area_sqm)} m²` : "", p.area_name ?? "",
    p.advance_months && p.deal_type === "rent" ? `${p.advance_months} ${p.advance_months === 1 ? "month" : "months"} upfront` : "",
    p.units_total && p.units_total > 1 ? `${p.units_available ?? 1} of ${p.units_total} units free` : "",
  ].filter(Boolean);
  const am = (p.amenities ?? []).map((a) => AMENITY[a]).filter(Boolean);
  const catHref = c?.slug ? `/${c.slug}` : isDemo(c ?? ({} as Catalog)) ? `/${DEMO_SLUG}` : null;

  const who = c
    ? `<${catHref ? `a href="${catHref}"` : "div"} class="agent">${avatar(c)}<div><b>${esc(c.name)}</b>
<div class="mut">${c.agency_name ? esc(c.agency_name) + " · " : ""}${c.role === "agent" ? "Agent" : "Owner"}${catHref ? " · See all properties" : ""}</div>
<div style="margin-top:4px">${badges(c).replace(/class="bdg"/g, 'class="mut" style="margin-right:8px"')}</div></div></${catHref ? "a" : "div"}>`
    : `<div class="agent"><div><div class="mut">Listed by</div><b>${esc(name)}</b></div></div>`;

  const body = `<div class="top" style="padding-bottom:14px"><div class="wrap"><div class="bar">
<a class="logo" href="/">ZUMI</a><a class="share" data-share href="${esc(`https://wa.me/?text=${encodeURIComponent(`${p.title} — ${priceLine(p)}\n${canonical}`)}`)}">Share</a></div></div></div>
<div class="wrap">
${fromCatalog && catHref ? `<a class="back" href="${catHref}">← ${esc(name)}'s catalogue</a>` : ""}
${pics.length ? `<div class="gal">${pics.map((u, i) => `<img src="${esc(u)}" alt="${esc(h)}" ${i ? 'loading="lazy"' : 'fetchpriority="high"'} decoding="async">`).join("")}</div>
${pics.length > 1 ? `<div class="mut" style="margin-top:6px">${pics.length} photos — swipe to see all</div>` : ""}` : ""}
<div class="price">${esc(priceLine(p))}</div>
<h1 style="color:#245045;font-size:22px;margin:4px 0">${esc(p.title)}</h1>
<div class="mut">${esc(h)}</div>
${facts.length ? `<div class="facts" style="margin-top:12px">${facts.map((f) => `<span>${esc(f)}</span>`).join("")}</div>` : ""}
${p.description ? `<h2>About this ${esc(typeName(p.property_type))}</h2><p style="margin:0">${esc(p.description).replace(/\n/g, "<br>")}</p>` : ""}
${am.length ? `<h2>Power, water and amenities</h2><div class="facts">${am.map((a) => `<span>${esc(a)}</span>`).join("")}</div>` : ""}
${who}
<div class="safe">Never pay a deposit or viewing fee before you have seen the property in person.</div>
${more.length ? `<h2>More ${esc(typeName(p.property_type, true))} to ${deal} in ${esc(p.area_name)}</h2><div class="grid">${more.map((m) => itemCard(m)).join("")}</div>` : ""}
<div class="foot">
<a class="made" href="${esc(app)}">See map, save and more homes on Zumi</a><br><br>
${p.area_name ? `<a href="/${deal}/${slugify(p.area_name)}">Homes to ${deal} in ${esc(p.area_name)}</a> · ` : ""}<a href="mailto:support@zumihome.com?subject=${encodeURIComponent(`Report: ${canonical}`)}">Report this listing</a>
</div>
</div>${shareScript(canonical, p.title)}`;

  return shell({
    type: "website",
    title: `${priceLine(p)} · ${h}`,
    description: [specs(p), (p.description ?? "").replace(/\s+/g, " ").slice(0, 140), c ? `Listed by ${c.name}` : ""].filter(Boolean).join(" · "),
    url: canonical, image: pics[0], body,
    jsonld: {
      "@context": "https://schema.org", "@type": "Offer", name: p.title, url: canonical,
      price: p.price, priceCurrency: p.currency || "ZMW", image: pics[0],
      itemOffered: { "@type": p.property_type === "land" ? "Place" : "Accommodation", name: h,
        address: { "@type": "PostalAddress", addressLocality: p.area_name ?? undefined, addressRegion: p.city ?? undefined, addressCountry: "ZM" } },
    },
    bar: contactBar(c, `Hi ${first}, I'm interested in "${p.title}" (${priceLine(p)}) on Zumi: ${url}`, app),
  });
}
