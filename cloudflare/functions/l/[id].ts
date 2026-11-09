// /l/<id> — объявление: превью для WhatsApp/Facebook и страница для Google; людей — сразу в приложение
import { card, esc, img as fullImg, headline, isBot, LISTING_COLS, Listing, notFound, page, priceLine, sb, SITE, specs, typeName, slug } from "../../lib/zumi";

export const onRequestGet: PagesFunction = async ({ request, params }) => {
  const id = String(params.id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return notFound();
  const app = `${SITE}/?listing=${id}`;
  if (!isBot(request)) return Response.redirect(app, 302);

  const rows = await sb<Listing[]>(`property_feed?select=${LISTING_COLS}&id=eq.${id}&status=eq.active&limit=1`).catch(() => []);
  const p = rows[0];
  if (!p) return notFound();
  const h = headline(p);
  const title = `${priceLine(p)} · ${h} — Zumi`;
  const desc = [specs(p), (p.description ?? "").replace(/\s+/g, " ").slice(0, 160)].filter(Boolean).join(" — ");
  const img = fullImg(p.image_urls?.[0] ?? p.thumb_urls?.[0]);
  const who = p.listed_by === "agent" ? (p.agency_name || p.owner_name || "Agent") : "Owner";
  const deal = p.deal_type === "rent" ? "rent" : "buy";
  const area = p.area_name ? `<a href="/${deal}/${slug(p.area_name)}">${esc(typeName(p.property_type, true))} to ${deal} in ${esc(p.area_name)}</a>` : "";
  const more = p.area_name
    ? await sb<Listing[]>(`property_feed?select=${LISTING_COLS}&status=eq.active&is_fresh=eq.true&area_name=eq.${encodeURIComponent(p.area_name)}&deal_type=eq.${p.deal_type}&id=neq.${id}&order=created_at.desc&limit=6`).catch(() => [])
    : [];
  return page({
    title, description: desc || h, url: `${SITE}/l/${id}`, image: img,
    jsonld: {
      "@context": "https://schema.org", "@type": "Offer", name: p.title, url: `${SITE}/l/${id}`,
      price: p.price, priceCurrency: p.currency || "ZMW", image: img,
      itemOffered: { "@type": p.property_type === "land" ? "Place" : "Accommodation", name: h,
        address: { "@type": "PostalAddress", addressLocality: p.area_name ?? undefined, addressRegion: p.city ?? undefined, addressCountry: "ZM" } },
    },
    body: `${img ? `<img class="hero" src="${esc(img)}" alt="${esc(h)}">` : ""}
<h1>${esc(p.title)}</h1>
<div class="price">${esc(priceLine(p))}</div>
<p class="muted">${esc(h)}${specs(p) ? ` · ${esc(specs(p))}` : ""} · Listed by ${esc(who)}</p>
<p><a class="btn" href="${app}">See photos, map and contact on Zumi</a></p>
${p.description ? `<h2>About this ${esc(typeName(p.property_type))}</h2><p>${esc(p.description).replace(/\n/g, "<br>")}</p>` : ""}
<p class="chips">${area}</p>
${more.length ? `<h2>More in ${esc(p.area_name)}</h2><div class="grid">${more.map(card).join("")}</div>` : ""}`,
  });
};
