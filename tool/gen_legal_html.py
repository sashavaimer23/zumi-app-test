#!/usr/bin/env python3
"""Делает web/privacy.html и web/terms.html из текстов lib/screens/legal_screen.dart.
Нужно для Google и Facebook (страницы политики по прямой ссылке) и для поиска.
Запускается в сборке (deploy.yml) — тексты всегда совпадают с приложением."""
import html, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / 'lib/screens/legal_screen.dart').read_text(encoding='utf-8')
updated = re.search(r"kLegalUpdated\s*=\s*'([^']*)'", src).group(1)
draft = re.search(r"kLegalDraft\s*=\s*(true|false)", src).group(1) == 'true'

STR = re.compile(r"'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"")

def unescape(s):
    return re.sub(r"\\(.)", lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)

def sections(name):
    m = re.search(r"const %s = <\(String, String\)>\[(.*?)\n\];" % name, src, re.S)
    if not m:
        sys.exit('cannot find ' + name)
    out = []
    # идём по кортежам «( строки , строки )»
    body = m.group(1)
    for tup in re.finditer(r"\(\s*(.*?)\s*\),?\s*(?=\(|\Z)", body, re.S):
        parts = []
        txt = tup.group(1)
        # делим по запятой верхнего уровня вне строк
        i, buf, inq = 0, '', None
        while i < len(txt):
            c = txt[i]
            if inq:
                buf += c
                if c == '\\':
                    buf += txt[i + 1]; i += 1
                elif c == inq:
                    inq = None
            elif c in "'\"":
                inq = c; buf += c
            elif c == ',':
                parts.append(buf); buf = ''
            else:
                buf += c
            i += 1
        if buf.strip():
            parts.append(buf)
        if len(parts) < 2:
            continue
        head = ''.join(unescape(a or b) for a, b in STR.findall(parts[0]))
        text = ''.join(unescape(a or b) for a, b in STR.findall(','.join(parts[1:])))
        out.append((head, text))
    return out

def para(text):
    blocks = []
    lines = text.split('\n')
    bullets = [l for l in lines if l.strip()]
    if bullets and all(l.lstrip().startswith('•') for l in bullets):
        return '<ul>' + ''.join('<li>%s</li>' % html.escape(l.lstrip('• ').strip()) for l in bullets) + '</ul>'
    for l in lines:
        if not l.strip():
            continue
        if l.lstrip().startswith('•'):
            blocks.append('<ul><li>%s</li></ul>' % html.escape(l.lstrip('• ').strip()))
        else:
            blocks.append('<p>%s</p>' % html.escape(l.strip()))
    return ''.join(blocks).replace('</ul><ul>', '')

def page(slug, title, secs, other):
    body = ''.join('<h2>%s</h2>%s' % (html.escape(h), para(t)) for h, t in secs)
    note = '<p class="draft">Draft — this text will be reviewed by a lawyer before Zumi launches.</p>' if draft else ''
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — Zumi</title>
<meta name="description" content="Zumi {title} — homes to rent and buy in Zambia.">
<link rel="canonical" href="https://zumihome.com/{slug}.html">
<link rel="icon" type="image/png" href="favicon.png">
<style>
body{{margin:0;background:#FBF7F2;color:#1F2A26;font:16px/1.6 -apple-system,Segoe UI,Roboto,Arial,sans-serif}}
main{{max-width:760px;margin:0 auto;padding:28px 18px 60px}}
a{{color:#C9583A}} header a{{color:#245045;font-weight:800;letter-spacing:2px;text-decoration:none;font-size:22px}}
h1{{color:#245045;font-size:30px;margin:26px 0 4px}} h2{{color:#245045;font-size:19px;margin:28px 0 6px}}
.muted{{color:#6E7A74;font-size:14px}} .draft{{background:#FDEBE3;padding:10px 14px;border-radius:12px;font-size:14px}}
ul{{padding-left:22px}} footer{{margin-top:40px;font-size:14px;color:#6E7A74}}
</style></head>
<body><main>
<header><a href="/">ZUMI</a></header>
<h1>{title}</h1>
<p class="muted">Last updated: {html.escape(updated)}</p>
{note}
{body}
<footer><a href="/">Open Zumi</a> · <a href="{other[0]}.html">{other[1]}</a> · Questions: <a href="mailto:support@zumihome.com">support@zumihome.com</a></footer>
</main></body></html>
'''

web = root / 'web'
(web / 'terms.html').write_text(page('terms', 'Terms of Service', sections('_terms'), ('privacy', 'Privacy Policy')), encoding='utf-8')
(web / 'privacy.html').write_text(page('privacy', 'Privacy Policy', sections('_privacy'), ('terms', 'Terms of Service')), encoding='utf-8')
print('legal pages:', len(sections('_terms')), 'terms sections,', len(sections('_privacy')), 'privacy sections')

# страница для Facebook / Google: как удалить аккаунт и данные
(web / 'delete-account.html').write_text(page('delete-account', 'Delete your account and data', [
    ('In the app', '• Open Zumi and sign in.\n• Go to Profile → Settings → Delete account.\n'
                   '• Confirm. Your profile, listings, photos and chats are deleted within 30 days.'),
    ('By email', 'If you cannot sign in, write to support@zumihome.com from the email of your account and ask us to '
                 'delete it. We answer within 7 days.'),
    ('Signed in with Google or Facebook?', 'Deleting your Zumi account removes the data Zumi got from Google or '
     'Facebook (your name, email and photo). You can also remove Zumi from the apps connected to your Google or '
     'Facebook account.'),
], ('privacy', 'Privacy Policy')), encoding='utf-8')
