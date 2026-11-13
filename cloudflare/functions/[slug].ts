// zumihome.com/<адрес> — каталог агента (портфолио). Видят все: люди, Google и WhatsApp-превью.
// Всё, что не похоже на адрес каталога (файлы сайта, /terms.html и т.д.), отдаём как обычно.
import { badges, avatar, contactBar, isSlug, itemCard, loadCatalog, loadItems, shareScript, shell } from "../lib/catalog";
import { esc, isBot, rpc, SITE, typeName } from "../lib/zumi";

export const onRequestGet: PagesFunction = async (ctx) => {
  const raw = String(ctx.params.slug ?? "");
  const slug = raw.toLowerCase();
  if (!isSlug(slug)) return ctx.next();
  if (raw !== slug) return Response.redirect(`${SITE}/${slug}`, 301);

  const c = await loadCatalog(slug);
  if (!c) return ctx.next(); // нет такого каталога — обычная страница «не найдено»
  const items = await loadItems(c.id);
  if (!isBot(ctx.request)) ctx.waitUntil(rpc("catalog_seen", { p_slug: slug }).catch(() => null));

  const url = `${SITE}/${slug}`;
  const first = c.name.split(/\s+/)[0] || c.name;
  const rent = items.filter((p) => p.deal_type === "rent").length;
  const sale = items.length - rent;
  const types = [...new Set(items.map((p) => p.property_type))];
  const what = rent && sale ? "homes for rent and sale" : rent ? "homes for rent" : sale ? "homes for sale" : "homes";
  const trust = [c.licensed ? "✓ Licensed agent" : "", c.phone_checked ? "✓ Number checked" : ""].filter(Boolean).join(" · ");
  const title = `${c.name}${c.agency_name ? ` · ${c.agency_name}` : ""} — property catalogue`;
  const description = [`${items.length} ${items.length === 1 ? "property" : what}${c.areas ? ` in ${c.areas}` : ""}`, trust]
    .filter(Boolean).join(" · ");
  const image = items[0]?.image_urls?.[0] ?? items[0]?.thumb_urls?.[0] ?? c.avatar_url;

  const tabs = [
    `<button class="on" data-f="all">All · ${items.length}</button>`,
    rent && sale ? `<button data-f="deal:rent">For rent · ${rent}</button><button data-f="deal:sale">For sale · ${sale}</button>` : "",
    types.length > 1 ? types.map((t) => `<button data-f="type:${t}">${esc(typeName(t, true)[0]!.toUpperCase() + typeName(t, true).slice(1))}</button>`).join("") : "",
  ].join("");

  const body = `<div class="top"><div class="wrap">
<div class="bar"><a class="logo" href="/">ZUMI</a><a class="share" data-share href="${esc(`https://wa.me/?text=${encodeURIComponent(`${title}\n${url}`)}`)}">Share</a></div>
<div class="who">${avatar(c)}<div><h1>${esc(c.name)}</h1>
<div class="ag">${c.agency_name ? esc(c.agency_name) : c.role === "agent" ? "Real estate agent" : "Property owner"}</div></div></div>
<div class="bdgs">${badges(c)}</div>
<div class="meta">${[c.areas ? `📍 ${esc(c.areas)}` : "", `${items.length} ${items.length === 1 ? "listing" : "listings"}`, c.since ? `On Zumi since ${esc(c.since)}` : ""].filter(Boolean).join(" · ")}</div>
${c.bio ? `<p class="bio">${esc(c.bio).replace(/\n/g, "<br>")}</p>` : ""}
</div></div>
<div class="wrap">
${items.length > 1 ? `<div class="tabs">${tabs}</div>` : ""}
${items.length ? `<div class="grid" id="g">${items.map((p) => itemCard(p, slug)).join("")}</div>`
    : `<div class="empty" style="margin-top:18px">No properties available right now — message ${esc(first)} to ask what is coming up.</div>`}
<div class="foot">Never pay before you have seen the property in person.<br>
<a href="mailto:support@zumihome.com?subject=${encodeURIComponent(`Report: ${url}`)}">Report this catalogue</a><br>
<a class="made" href="/agents">Agent? Make your free catalogue on Zumi</a></div>
</div>
<script>
var bs=document.querySelectorAll('.tabs button'),cs=document.querySelectorAll('#g .card');
bs.forEach(function(b){b.onclick=function(){bs.forEach(function(x){x.classList.remove('on')});b.classList.add('on');
var f=b.dataset.f.split(':');cs.forEach(function(c){c.style.display=(f[0]==='all'||c.dataset[f[0]]===f[1])?'':'none'})}});
</script>${shareScript(url, title)}`;

  return shell({
    title, description: description || "Property catalogue on Zumi", url, image, body,
    bar: contactBar(c, `Hi ${first}, I saw your property catalogue on Zumi (${url}). `),
  });
};

