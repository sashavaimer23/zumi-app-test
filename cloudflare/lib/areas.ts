// Страницы районов для Google: «Houses for rent in Roma», «2 bedroom flats for rent in Kabulonga»
import { card, esc, LISTING_COLS, Listing, money, page, sb, SITE, slug, typeName } from "./zumi";

type Area = { id: string; name: string; city: string | null; kind: string | null };

const TYPE_SLUGS: Record<string, string> = { houses: "house", flats: "apartment", apartments: "apartment",
  plots: "land", land: "land", commercial: "commercial", offices: "commercial", rooms: "room" };

export async function areas(): Promise<Area[]> {
  return await sb<Area[]>("areas?select=id,name,city,kind&order=name").catch(() => []);
}

// «2-bedroom-flats» → {beds: 2, type: 'apartment'}
function parseFilter(f?: string): { beds?: number; type?: string } | null {
  if (!f) return {};
  const m = f.match(/^(?:(\d)-bedroom-)?([a-z]+)$/);
  if (!m || !TYPE_SLUGS[m[2]]) return null;
  return { beds: m[1] ? Number(m[1]) : undefined, type: TYPE_SLUGS[m[2]] };
}

export async function areaPage(deal: "rent" | "sale", parts: string[]): Promise<Response> {
  const verb = deal === "rent" ? "rent" : "buy";
  const forWhat = deal === "rent" ? "for rent" : "for sale";
  const all = await areas();
  // /rent — список районов
  if (parts.length === 0) {
    return page({
      title: `Homes ${forWhat} in Lusaka and Zambia by neighbourhood | Zumi`,
      description: `Houses, flats and plots ${forWhat} in every Lusaka neighbourhood — verified agents and owners on Zumi.`,
      url: `${SITE}/${verb}`,
      body: `<h1>Homes ${forWhat} by neighbourhood</h1><p class="chips">${all.map((a) =>
        `<a href="/${verb}/${slug(a.name)}">${esc(a.name)}</a>`).join("")}</p>`,
    });
  }
  const area = all.find((a) => slug(a.name) === parts[0]);
  const f = parseFilter(parts[1]);
  if (!area || !f || parts.length > 2) return Response.redirect(`${SITE}/${verb}`, 302);

  let q = `property_feed?select=${LISTING_COLS}&status=eq.active&is_fresh=eq.true&deal_type=eq.${deal}&area_id=eq.${area.id}`;
  if (f.type) q += `&property_type=eq.${f.type}`;
  if (f.beds) q += `&bedrooms=eq.${f.beds}`;
  const list = await sb<Listing[]>(`${q}&order=created_at.desc&limit=60`).catch(() => []);

  const what = f.type ? typeName(f.type, true) : "homes";
  const beds = f.beds ? `${f.beds} bedroom ` : "";
  const place = `${area.name}${area.city ? `, ${area.city}` : ""}`;
  const h1 = `${beds}${what} ${forWhat} in ${place}`.replace(/^./, (c) => c.toUpperCase());
  const prices = list.map((p) => p.price).filter((n) => n > 0).sort((a, b) => a - b);
  const per = deal === "rent" ? " a month" : "";
  const range = !prices.length ? ""
    : prices[0] === prices[prices.length - 1] ? ` Price: ${money(prices[0])}${per}.`
    : ` Prices from ${money(prices[0])} to ${money(prices[prices.length - 1])}${per}.`;
  const intro = list.length
    ? `${list.length} ${list.length === 1 ? "listing" : "listings"} right now.${range} Every listing shows who posts it — owner or agent — and agents show their ZIEA licence.`
    : `No ${what} ${forWhat} in ${area.name} right now. New homes are added every day — check Zumi or look at nearby neighbourhoods.`;
  const base = `/${verb}/${slug(area.name)}`;
  const filters = ["houses", "flats", "1-bedroom-flats", "2-bedroom-flats", "3-bedroom-houses", "4-bedroom-houses",
    ...(deal === "sale" ? ["plots"] : [])];
  return page({
    title: `${h1} | Zumi`,
    description: `${intro}`.slice(0, 160),
    url: `${SITE}${base}${parts[1] ? `/${parts[1]}` : ""}`,
    image: list[0]?.image_urls?.[0],
    noindex: list.length === 0,
    body: `<h1>${esc(h1)}</h1><p>${esc(intro)}</p>
<p><a class="btn" href="/">Search on the map in Zumi</a></p>
<p class="chips"><a href="${base}">All ${verb === "rent" ? "rentals" : "for sale"}</a>${filters.map((x) =>
      `<a href="${base}/${x}">${esc(x.replace(/-/g, " "))}</a>`).join("")}</p>
<div class="grid">${list.map(card).join("")}</div>
<h2>Other neighbourhoods</h2><p class="chips">${all.filter((a) => a.id !== area.id).slice(0, 40).map((a) =>
      `<a href="/${verb}/${slug(a.name)}${parts[1] ? `/${parts[1]}` : ""}">${esc(a.name)}</a>`).join("")}</p>`,
  });
}
