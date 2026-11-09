// /agency/<id> — витрина агентства
import { card, esc, isBot, LISTING_COLS, Listing, notFound, page, rpc, sb, SITE } from "../../lib/zumi";

type Agency = { id: string; name: string; logo_url: string | null; about: string | null; verified: boolean;
  members: { id: string; full_name: string | null; licensed: boolean }[]; active_listings: number };

export const onRequestGet: PagesFunction = async ({ request, params }) => {
  const id = String(params.id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return notFound();
  const app = `${SITE}/?agency=${id}`;
  if (!isBot(request)) return Response.redirect(app, 302);
  const a = await rpc<Agency | null>("agency_page", { p_id: id }).catch(() => null);
  if (!a) return notFound();
  const ids = a.members.map((m) => m.id).join(",");
  const list = ids
    ? await sb<Listing[]>(`property_feed?select=${LISTING_COLS}&owner_id=in.(${ids})&status=eq.active&is_fresh=eq.true&order=created_at.desc&limit=80`).catch(() => [])
    : [];
  return page({
    title: `${a.name} — real estate agency in Zambia | Zumi`,
    description: `${a.members.length} agents, ${list.length} homes to rent and buy. ${a.verified ? "Registered firm (ZIEA). " : ""}${(a.about ?? "").slice(0, 120)}`,
    url: `${SITE}/agency/${id}`, image: list[0]?.image_urls?.[0] ?? a.logo_url,
    body: `<h1>${esc(a.name)}</h1><p class="muted">Real estate agency${a.verified ? " · ✓ Registered firm (ZIEA)" : ""} · ${a.members.length} agents</p>
${a.about ? `<p>${esc(a.about)}</p>` : ""}<p><a class="btn" href="${app}">Open on Zumi</a></p>
<h2>Agents</h2><p class="chips">${a.members.map((m) => `<a href="/agent/${m.id}">${esc(m.full_name || "Agent")}${m.licensed ? " ✓" : ""}</a>`).join("")}</p>
<h2>Listings (${list.length})</h2><div class="grid">${list.map(card).join("")}</div>`,
  });
};
