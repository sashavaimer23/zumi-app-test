// Карта сайта для Google: главная, районы, объявления, агентства
import { areas } from "../lib/areas";
import { sb, SITE, slug } from "../lib/zumi";

export const onRequestGet: PagesFunction = async () => {
  const [all, listings, agencies] = await Promise.all([
    areas(),
    sb<{ id: string; updated_at: string; area_id: string | null; deal_type: string }[]>(
      "property_feed?select=id,updated_at,area_id,deal_type&status=eq.active&is_fresh=eq.true&is_demo=eq.false&limit=5000").catch(() => []),
    sb<{ id: string; updated_at: string }[]>("agencies?select=id,updated_at&limit=1000").catch(() => []),
  ]);
  const withRent = new Set(listings.filter((l) => l.deal_type === "rent").map((l) => l.area_id));
  const withSale = new Set(listings.filter((l) => l.deal_type === "sale").map((l) => l.area_id));
  const u = (loc: string, last?: string) => `<url><loc>${SITE}${loc}</loc>${last ? `<lastmod>${last.slice(0, 10)}</lastmod>` : ""}</url>`;
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${u("/")}${u("/agents")}${u("/rent")}${u("/buy")}
${all.filter((a) => withRent.has(a.id)).map((a) => u(`/rent/${slug(a.name)}`)).join("")}
${all.filter((a) => withSale.has(a.id)).map((a) => u(`/buy/${slug(a.name)}`)).join("")}
${listings.map((l) => u(`/l/${l.id}`, l.updated_at)).join("")}
${agencies.map((a) => u(`/agency/${a.id}`, a.updated_at)).join("")}
</urlset>`;
  return new Response(xml, { headers: { "Content-Type": "application/xml", "Cache-Control": "public, max-age=3600" } });
};
