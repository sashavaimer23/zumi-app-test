// /agent/<id> — витрина агента: превью для мессенджеров и страница для Google; людей — в приложение
import { card, esc, isBot, LISTING_COLS, Listing, notFound, page, rpc, sb, SITE } from "../../lib/zumi";

type Pub = { id: string; role: string; full_name: string | null; agency_name: string | null; avatar_url: string | null;
  bio: string | null; licence_verified: boolean; active_listings: number };

export const onRequestGet: PagesFunction = async ({ request, params }) => {
  const id = String(params.id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return notFound();
  const app = `${SITE}/?agent=${id}`;
  if (!isBot(request)) return Response.redirect(app, 302);
  const pr = (await rpc<Pub[]>("public_profile", { uid: id }).catch(() => []))[0];
  if (!pr) return notFound();
  const list = await sb<Listing[]>(`property_feed?select=${LISTING_COLS}&owner_id=eq.${id}&status=eq.active&is_fresh=eq.true&order=created_at.desc&limit=60`).catch(() => []);
  const name = pr.full_name || (pr.role === "agent" ? "Agent" : "Owner");
  const what = pr.role === "agent" ? `Real estate agent${pr.agency_name ? ` · ${pr.agency_name}` : ""}` : "Property owner";
  const title = `${name} — ${list.length} ${list.length === 1 ? "listing" : "listings"} on Zumi`;
  const img = list[0]?.image_urls?.[0] ?? pr.avatar_url;
  return page({
    title, description: `${what} in Zambia. ${pr.licence_verified ? "ZIEA licensed. " : ""}See all homes on Zumi.`,
    url: `${SITE}/agent/${id}`, image: img,
    body: `<h1>${esc(name)}</h1><p class="muted">${esc(what)}${pr.licence_verified ? " · ✓ Licensed agent (ZIEA)" : ""}</p>
${pr.bio ? `<p>${esc(pr.bio)}</p>` : ""}<p><a class="btn" href="${app}">Open on Zumi</a></p>
<h2>Listings (${list.length})</h2><div class="grid">${list.map(card).join("")}</div>`,
  });
};
