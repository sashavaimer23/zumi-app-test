// /agents — «Zumi для агентов»: страница, которую отправляем агентам, когда зовём их на Zumi.
// Видят все (и люди, и Google, и WhatsApp-превью). Кнопки ведут в регистрацию с уже выбранной ролью.
// Про лицензию — специально мягко: в Замбии она есть не у всех, без неё тоже можно.
import { page, SITE } from "../lib/zumi";

const css = `<style>
.lead{font-size:18px;max-width:640px}
.cta{display:flex;flex-wrap:wrap;gap:10px;margin:18px 0 6px}
.btn2{display:inline-block;background:#fff;color:#245045;border:2px solid #245045;text-decoration:none;font-weight:700;padding:10px 20px;border-radius:24px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:24px 0 8px}
.stat{background:#fff;border-radius:18px;padding:16px}
.stat b{display:block;color:#245045;font-size:28px;line-height:1.1}
.stat span{color:#6E7A74;font-size:14px}
.feats{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.feat{background:#fff;border-radius:18px;padding:18px}
.feat h3{margin:0 0 6px;color:#245045;font-size:17px}
.feat p{margin:0;color:#4A5651;font-size:15px}
.note{background:#E8EFEA;border-radius:18px;padding:18px 20px;margin:20px 0}
.note h2{margin-top:0}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:18px;overflow:hidden}
td,th{padding:12px 16px;text-align:left;border-bottom:1px solid #F0EBE4;font-size:15px}
th{color:#6E7A74;font-weight:600;font-size:13px;text-transform:uppercase;letter-spacing:.5px}
td b{color:#245045}
.steps{counter-reset:s;list-style:none;padding:0;margin:0;display:grid;gap:10px}
.steps li{background:#fff;border-radius:18px;padding:14px 18px 14px 58px;position:relative}
.steps li:before{counter-increment:s;content:counter(s);position:absolute;left:16px;top:12px;width:30px;height:30px;border-radius:50%;background:#F07A5A;color:#fff;font-weight:700;display:flex;align-items:center;justify-content:center}
details{background:#fff;border-radius:14px;padding:14px 18px;margin-bottom:10px}
summary{cursor:pointer;font-weight:700;color:#245045}
details p{margin:8px 0 0;color:#4A5651}
.final{text-align:center;background:#245045;color:#fff;border-radius:22px;padding:28px 18px;margin-top:30px}
.final h2{color:#fff;margin-top:0}
@media(max-width:520px){h1{font-size:26px}.lead{font-size:16px}.cta .btn,.cta .btn2{width:100%;text-align:center;box-sizing:border-box}}
</style>`;

const join = "/?signup=agent";
const agency = "/?signup=agency";

const faq: [string, string][] = [
  ["Is it really free?",
    "Yes. Posting up to your limit costs nothing and there is no commission — the deal is between you and your client. " +
    "Later we may add optional extras (like boosting a listing to the top), but your free listings stay free."],
  ["Do I need a ZIEA licence?",
    "No. You can sign up and post right away without one. If you have a licence, add your registration number " +
    "and you get the \"Licensed agent\" badge and 5 extra free listings."],
  ["Who sees my phone number?",
    "Only people signed in to Zumi. Anyone can also write to you in the Zumi chat, so you never miss a client."],
  ["How do clients contact me?",
    "They call you, message you on WhatsApp or write in the Zumi chat. We send you an email if a message waits for you."],
  ["What happens when a property is taken?",
    "Mark it as rented or sold in one tap. Once a week we ask \"Still available?\" — this keeps Zumi free of old " +
    "listings, so clients trust what they see and call you about homes that are really free."],
  ["Can my whole team join?",
    "Yes. Register your agency, then invite colleagues with a link. The agency shares 25 free listings and gets its own page with all your properties."],
];

export const onRequestGet: PagesFunction = async () =>
  page({
    title: "Zumi for agents — list properties in Zambia for free",
    description: "Post up to 10 listings free (15 with a ZIEA licence, 25 for agencies). No commission. " +
      "Clients call, WhatsApp or chat with you directly. Licence not required.",
    url: `${SITE}/agents`,
    body: `${css}
<h1>Get more clients. List your properties on Zumi — free</h1>
<p class="lead">Zumi is a home search for Zambia where tenants and buyers contact you directly. No commission, no fees to post, no licence required.</p>
<div class="cta"><a class="btn" href="${join}">Join as an agent</a><a class="btn2" href="${agency}">Register an agency</a></div>

<div class="stats">
<div class="stat"><b>10</b><span>free listings for every agent</span></div>
<div class="stat"><b>15</b><span>with a ZIEA licence</span></div>
<div class="stat"><b>25</b><span>shared by an agency team</span></div>
<div class="stat"><b>0%</b><span>commission — the deal is yours</span></div>
</div>

<h2>Why agents use Zumi</h2>
<div class="feats">
<div class="feat"><h3>Clients come to you</h3><p>People call, WhatsApp or chat with you straight from your listing. No middleman.</p></div>
<div class="feat"><h3>Your own agent page</h3><p>All your properties on one page. Share one link in WhatsApp groups and on Facebook.</p></div>
<div class="feat"><h3>People trust what they see</h3><p>Our team checks listings and removes old ones. Clients feel safe — and call.</p></div>
<div class="feat"><h3>Looks great in WhatsApp</h3><p>Your listing links show a photo, price and area — not a bare link.</p></div>
</div>

<div class="note">
<h2>No licence? You can still join</h2>
<p>Many good agents in Zambia work without a ZIEA licence. Sign up and start posting today — 10 listings are free.</p>
<p>Have a licence? Add your registration number. We check it and you get the <b>Licensed agent</b> badge and <b>5 extra</b> free listings.</p>
</div>

<h2>Free listings</h2>
<table>
<tr><th>Account</th><th>Free listings</th></tr>
<tr><td>Agent</td><td><b>10</b></td></tr>
<tr><td>Agent with a ZIEA licence</td><td><b>15</b></td></tr>
<tr><td>Agency (whole team)</td><td><b>25</b> shared</td></tr>
</table>
<p class="muted">For our first agents: what you post during the launch stays up — if plans change later, we never remove listings that follow our rules.</p>

<h2>Badges that build trust</h2>
<div class="feats">
<div class="feat"><h3>✓ Number checked</h3><p>Confirm your phone with a code. Clients see that your number is real.</p></div>
<div class="feat"><h3>✓ Licensed agent</h3><p>Optional. For agents with a ZIEA licence that our team has checked.</p></div>
</div>

<h2>For agencies</h2>
<p>One agency account for your whole team: invite colleagues with a link, share 25 free listings and get an agency page with all your properties and agents.</p>
<p><a class="btn2" href="${agency}">Register an agency</a></p>

<h2>Start in 3 steps</h2>
<ol class="steps">
<li><b>Sign up as an agent</b> — email or Google, about a minute.</li>
<li><b>Add a property</b> — photos, price, area. We check it quickly.</li>
<li><b>Get calls and messages</b> — from people looking for exactly that home.</li>
</ol>

<h2>Questions</h2>
${faq.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join("")}

<div class="final">
<h2>Ready to get more clients?</h2>
<p>Free to join. No licence required.</p>
<a class="btn" href="${join}">Join as an agent</a>
<p style="margin:14px 0 0;font-size:14px">Questions? Write to <a style="color:#fff" href="mailto:hello@zumihome.com">hello@zumihome.com</a></p>
</div>`,
  });
