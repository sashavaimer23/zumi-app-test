// zumihome.com/<адрес> — каталог агента (портфолио). Видят все: люди, Google и WhatsApp-превью.
// Всё, что не похоже на адрес каталога (файлы сайта, /terms.html и т.д.), отдаём как обычно.
import { badges, avatar, contactBar, DEMO_SLUG, isDemo, isSlug, itemCard, loadCatalog, loadItems, shareScript, shell } from "../lib/catalog";
import { esc, isBot, rpc, SITE, typeName } from "../lib/zumi";

export const onRequestGet: PagesFunction = async (ctx) => {
  const raw = String(ctx.params.slug ?? "");
  const slug = raw.toLowerCase();
  if (!isSlug(slug) && slug !== DEMO_SLUG) return ctx.next();
  if (raw !== slug) return Response.redirect(`${SITE}/${slug}`, 301);

  const c = await loadCatalog(slug);
  if (!c) return ctx.next(); // нет такого каталога — обычная страница «не найдено»
  const items = await loadItems(c.id);
  if (!isBot(ctx.request) && !isDemo(c)) ctx.waitUntil(rpc("catalog_seen", { p_slug: slug }).catch(() => null));

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

  const SHORT: Record<string, string> = { house: "Houses", apartment: "Flats", room: "Rooms", land: "Plots", commercial: "Commercial" };
  const seg = rent && sale
    ? `<div class="seg"><button class="on" data-deal="all">All</button><button data-deal="rent">For rent · ${rent}</button><button data-deal="sale">For sale · ${sale}</button></div>`
    : "";
  const typeBtns = types.length > 1
    ? `<div class="types">${types.map((t) => `<button data-type="${t}">${esc(SHORT[t] ?? typeName(t, true))}</button>`).join("")}</div>`
    : "";

  // сколько районов — по самим объектам (у агента объекты могут быть в разных районах); «Works in» — только если агент сам указал
  const areasN = new Set(items.map((p) => p.area_name).filter(Boolean)).size;
  const body = `<div class="top"><div class="wrap">
<div class="bar"><a class="logo" href="/">ZUMI</a><a class="share" data-share href="${esc(`https://wa.me/?text=${encodeURIComponent(`${title}\n${url}`)}`)}">Share</a></div>
</div></div>
<div class="wrap"><div class="prof">
${avatar(c)}
<h1>${esc(c.name)}</h1>
<div class="ag">${c.agency_name ? esc(c.agency_name) : c.role === "agent" ? "Real estate agent" : "Property owner"}</div>
${badges(c) ? `<div class="bdgs">${badges(c)}</div>` : ""}
<div class="stats">
<div><b>${items.length}</b><span>${items.length === 1 ? "property" : "properties"}</span></div>
${areasN ? `<div><b>${areasN}</b><span>${areasN === 1 ? "area" : "areas"}</span></div>` : ""}
${c.since ? `<div><b>${esc(c.since)}</b><span>on Zumi since</span></div>` : ""}
</div>
${c.areas ? `<div class="areas"><small>Works in</small>${esc(c.areas.split(",").map((x) => x.trim()).filter(Boolean).join(" · "))}</div>` : ""}
${c.bio ? `<p class="bio">${esc(c.bio).replace(/\n/g, "<br>")}</p>` : ""}
</div></div>
<div class="wrap">
${isDemo(c) ? `<p class="note">Example catalogue with sample homes · <a href="/agents">make your own</a></p>` : ""}
<div class="sec"><h2>Properties<span>${items.length}</span></h2></div>
${seg || typeBtns ? `<div class="filters">${seg}${typeBtns}</div>` : ""}
${items.length ? `<div class="grid" id="g">${items.map((p) => itemCard(p, slug)).join("")}</div>`
    : `<div class="empty" style="margin-top:18px">No properties available right now — message ${esc(first)} to ask what is coming up.</div>`}
<div class="foot">Never pay before you have seen the property in person.<br>
<a href="mailto:support@zumihome.com?subject=${encodeURIComponent(`Report: ${url}`)}">Report this catalogue</a><br>
<a class="made" href="/agents">Agent? Make your free catalogue on Zumi</a></div>
</div>
<script>
var deal='all',type='',cs=document.querySelectorAll('#g .card');
function apply(){cs.forEach(function(c){c.style.display=(deal==='all'||c.dataset.deal===deal)&&(!type||c.dataset.type===type)?'':'none'})}
document.querySelectorAll('.seg button').forEach(function(b,i,all){b.onclick=function(){all.forEach(function(x){x.classList.remove('on')});b.classList.add('on');deal=b.dataset.deal;apply()}});
document.querySelectorAll('.types button').forEach(function(b,i,all){b.onclick=function(){var on=!b.classList.contains('on');all.forEach(function(x){x.classList.remove('on')});if(on)b.classList.add('on');type=on?b.dataset.type:'';apply()}});
</script>${shareScript(url, title)}`;

  return shell({
    title, description: description || "Property catalogue on Zumi", url, image, body,
    bar: contactBar(c, `Hi ${first}, I saw your property catalogue on Zumi (${url}). `),
  });
};

