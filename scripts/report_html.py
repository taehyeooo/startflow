# 자동화 리포트(HTML) 만들기 — devflow·qaflow·uiflow·benchflow·startflow가 같은 파일을 하나씩 가진다(플러그인을 따로 설치해도 동작).
#   python3 report_html.py <리포트.json>      → ~/.config/flow-reports/<플러그인>/<시각>-<종류>.html, 목록 페이지 갱신, 경로 출력
# 리포트 JSON: { plugin, kind, title, summary, env, status: "ok"|"warn"|"fail", sections: [
#   {heading, table: {columns: [...], rows: [[...]]}} | {heading, images: [{label, path}]} | {heading, text: "..."} |
#   {heading, kv: [[이름, 값], ...]} | {heading, bars: {unit, items: [[이름, 값], ...]}} ] }
import html, json, os, sys, datetime, base64, mimetypes
src = json.load(open(sys.argv[1]))
root = os.path.expanduser(os.environ.get("FLOW_REPORT_DIR", "~/.config/flow-reports"))
now = datetime.datetime.now()
plugin, kind = src.get("plugin", "flow"), src.get("kind", "report")
outdir = os.path.join(root, plugin); os.makedirs(outdir, exist_ok=True)
out = os.path.join(outdir, f"{now:%Y%m%d-%H%M%S}-{kind}.html")
n = 2
while os.path.exists(out):  # 같은 초에 두 번 만들면 덮어쓰지 않게
    out = os.path.join(outdir, f"{now:%Y%m%d-%H%M%S}-{kind}-{n}.html"); n += 1
e = lambda s: html.escape(str(s))
STATUS = {"ok": ("정상", "ok"), "warn": ("확인 필요", "warn"), "fail": ("실패", "fail")}
CSS = """
:root{--bg:#fbfbf9;--card:#fff;--ink:#16211d;--muted:#5f5e5a;--line:#e6e5df;--accent:#e14a2b;--ok:#1f7a4d;--warn:#a86400;--fail:#b3261e}
@media (prefers-color-scheme:dark){:root{--bg:#141716;--card:#1d2120;--ink:#ecebe6;--muted:#a9a8a2;--line:#2e3331;--accent:#ff7a5c;--ok:#5fc48f;--warn:#f0b250;--fail:#ff8a80}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Noto Sans KR",sans-serif}
main{max-width:980px;margin:0 auto;padding:32px 20px 64px}header{margin-bottom:24px}
.tag{display:inline-block;white-space:nowrap;font-size:12px;padding:2px 10px;border-radius:999px;border:1px solid var(--line);color:var(--muted);margin-right:6px}
.st{font-weight:600}.st.ok{color:var(--ok);border-color:var(--ok)}.st.warn{color:var(--warn);border-color:var(--warn)}.st.fail{color:var(--fail);border-color:var(--fail)}
h1{font-size:24px;margin:10px 0 6px}h2{font-size:17px;margin:0 0 12px}.sum{color:var(--muted);margin:0}
section{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px 20px;margin:16px 0}
.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:600;white-space:nowrap}
.imgs{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px}.imgs figure{margin:0}.imgs img{width:100%;border:1px solid var(--line);border-radius:8px}.imgs figcaption{font-size:13px;color:var(--muted);margin-top:4px}
.kv{display:grid;grid-template-columns:max-content 1fr;gap:6px 18px;font-size:14px}.kv b{color:var(--muted);font-weight:600}
.bar{display:grid;grid-template-columns:minmax(120px,240px) 1fr max-content;gap:10px;align-items:center;font-size:14px;margin:6px 0}.bar i{display:block;height:14px;border-radius:4px;background:var(--muted);opacity:.55}.bar i.hi{background:var(--accent);opacity:1}
pre{white-space:pre-wrap;font-size:13px;background:var(--bg);padding:10px;border-radius:8px;margin:0}
footer{color:var(--muted);font-size:12px;margin-top:28px}a{color:var(--accent)}
"""
def img_src(p):
    p = os.path.expanduser(p)
    if os.path.exists(p) and os.path.getsize(p) < 3_500_000:  # 작은 이미지는 파일 안에 넣어 리포트만 옮겨도 보이게
        mt = mimetypes.guess_type(p)[0] or "image/png"
        return f"data:{mt};base64," + base64.b64encode(open(p, "rb").read()).decode()
    return "file://" + p
def section(s):
    h = f"<section><h2>{e(s.get('heading', ''))}</h2>"
    if "table" in s:
        t = s["table"]; h += "<div class=tw><table><thead><tr>" + "".join(f"<th>{e(c)}</th>" for c in t["columns"]) + "</tr></thead><tbody>"
        h += "".join("<tr>" + "".join(f"<td>{e(c)}</td>" for c in r) + "</tr>" for r in t["rows"]) + "</tbody></table></div>"
    if "images" in s:
        h += "<div class=imgs>" + "".join(f"<figure><a href='{img_src(i['path'])}' target=_blank><img src='{img_src(i['path'])}' alt='{e(i.get('label',''))}'></a><figcaption>{e(i.get('label',''))}</figcaption></figure>" for i in s["images"]) + "</div>"
    if "kv" in s:
        h += "<div class=kv>" + "".join(f"<b>{e(k)}</b><span>{e(v)}</span>" for k, v in s["kv"]) + "</div>"
    if "bars" in s:
        b = s["bars"]; mx = max([float(v) for _, v in b["items"]] or [1]) or 1; hi = b.get("highlight")
        h += "".join(f"<div class=bar><span>{e(n)}</span><i class='{ 'hi' if n == hi else ''}' style='width:{float(v)/mx*100:.1f}%'></i><span>{e(v)}{e(b.get('unit',''))}</span></div>" for n, v in b["items"])
    if "text" in s:
        h += f"<pre>{e(s['text'])}</pre>"
    return h + "</section>"
label, cls = STATUS.get(src.get("status", "ok"), STATUS["ok"])
page = f"""<!doctype html><html lang=ko><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>{e(src.get('title'))}</title><style>{CSS}</style><main>
<header><span class=tag>{e(plugin)}</span><span class=tag>{e(kind)}</span><span class='tag st {cls}'>{label}</span>
<h1>{e(src.get('title'))}</h1><p class=sum>{e(src.get('summary',''))}</p><p class=sum>실행 환경: {e(src.get('env','-'))} · {now:%Y-%m-%d %H:%M}</p></header>
{''.join(section(s) for s in src.get('sections', []))}
<footer><a href='../index.html'>전체 리포트 목록</a></footer></main></html>"""
open(out, "w").write(page)
# 목록 페이지(모든 플러그인 공용)
idx = os.path.join(root, "index.json")
items = json.load(open(idx)) if os.path.exists(idx) else []
items.insert(0, {"at": f"{now:%Y-%m-%d %H:%M}", "plugin": plugin, "kind": kind, "title": src.get("title"), "status": src.get("status", "ok"),
                 "summary": src.get("summary", ""), "file": os.path.relpath(out, root)})
items = items[:500]; json.dump(items, open(idx, "w"), ensure_ascii=False, indent=1)
rows = "".join(f"<tr><td>{e(i['at'])}</td><td><span class=tag>{e(i['plugin'])}</span></td><td><span class='tag st {STATUS.get(i['status'],STATUS['ok'])[1]}'>{STATUS.get(i['status'],STATUS['ok'])[0]}</span></td><td><a href='{e(i['file'])}'>{e(i['title'])}</a><br><small>{e(i['summary'])}</small></td></tr>" for i in items)
counts = {}
for i in items: counts[i["plugin"]] = counts.get(i["plugin"], 0) + 1
open(os.path.join(root, "index.html"), "w").write(f"""<!doctype html><html lang=ko><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>자동화 리포트</title><style>{CSS}</style><main>
<header><h1>자동화 리포트</h1><p class=sum>{' · '.join(f'{k} {v}건' for k, v in counts.items())} — 새 리포트가 위</p></header>
<section><div class=tw><table><thead><tr><th>시각</th><th>플러그인</th><th>결과</th><th>리포트</th></tr></thead><tbody>{rows}</tbody></table></div></section></main></html>""")
print(out)
