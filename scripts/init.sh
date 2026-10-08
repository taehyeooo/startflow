#!/usr/bin/env bash
# 새 서비스 처음 세팅: 답변(JSON)으로 나만의 기본값 파일을 만든다. 이미 있는 파일은 덮어쓰지 않는다
# (CLAUDE.md가 있으면 CLAUDE.startflow.md로 옆에 만들어 비교하게).
#   init.sh <답변.json> [--dry-run]
# 답변: name, summary, stack[], coreRisk, endpoints, codeStyle[], buildCmd, dontExtra[], envKeys[], hasUi, allow[]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A=${1:?답변 JSON}; DRY=0; [ "${2:-}" = "--dry-run" ] && DRY=1
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true); REPO=$(basename "${url%.git}"); REPO=${REPO:-$(basename "$ROOT")}
export REPORT_JSON=$(mktemp)
python3 - "$DIR" "$A" "$ROOT" "$REPO" "$DRY" <<'PY'
import json, os, sys, string
D, A, ROOT, REPO, DRY = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "1"
a = json.load(open(A))
bul = lambda xs: "\n".join(f"- {x}" for x in xs) if xs else "- (정하면 채우기)"
v = {
  "name": a["name"], "summary": a.get("summary", ""),
  "stack": bul(a.get("stack", [])), "coreRisk": a.get("coreRisk", "핵심 기능"),
  "endpoints": a.get("endpoints", "(설계하면 채우기)"),
  "codeStyle": bul(a.get("codeStyle", [])), "buildCmd": a.get("buildCmd", "(빌드·테스트 명령)"),
  "dontExtra": "\n".join(f"- {x}" for x in a.get("dontExtra", [])),
  "envKeys": "\n".join(f"{k}=" for k in a.get("envKeys", [])),
}
tpl = lambda f: string.Template(open(os.path.join(D, "templates", f)).read()).safe_substitute(v)
done = []
def write(path, text, keep_existing=True):
    full = os.path.join(ROOT, path)
    if os.path.exists(full) and open(full).read() == text:
        done.append(f"같음(그대로): {path}"); return
    if os.path.exists(full) and keep_existing:
        base, ext = os.path.splitext(full); full = base + ".startflow" + ext
        if os.path.exists(full): done.append(f"건너뜀(이미 있음): {path}"); return
    done.append(f"{'(미리보기) ' if DRY else ''}만듦: {os.path.relpath(full, ROOT)}")
    if not DRY:
        os.makedirs(os.path.dirname(full) or ".", exist_ok=True); open(full, "w").write(text)
write("CLAUDE.md", tpl("CLAUDE.md"))
write("docs/experience-notes.md", tpl("experience-notes.md"))
write(".env.example", tpl("env.example"))
write("docs/bench/.gitkeep", "")
# .gitignore: 시크릿 블록이 없을 때만 덧붙임
gi = os.path.join(ROOT, ".gitignore"); cur = open(gi).read() if os.path.exists(gi) else ""
if "(startflow)" not in cur:
    done.append(f"{'(미리보기) ' if DRY else ''}덧붙임: .gitignore 시크릿 블록")
    if not DRY: open(gi, "a").write(open(os.path.join(D, "templates", "gitignore-secrets")).read())
# 프로젝트 권한: 빌드·테스트·git add/commit은 묻지 않게(이전 프로젝트에서 매번 허용했던 것)
sp = os.path.join(ROOT, ".claude", "settings.json")
s = json.load(open(sp)) if os.path.exists(sp) else {}
allow = s.setdefault("permissions", {}).setdefault("allow", [])
for p in ["Bash(git add *)", "Bash(git commit *)", "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)"] + a.get("allow", []):
    if p not in allow: allow.append(p)
done.append(f"{'(미리보기) ' if DRY else ''}권한: .claude/settings.json allow {len(allow)}개")
if not DRY:
    os.makedirs(os.path.dirname(sp), exist_ok=True); json.dump(s, open(sp, "w"), ensure_ascii=False, indent=2)
# 플러그인 설정 뼈대(레포 밖). 이미 있으면 그대로.
H = os.path.expanduser("~")
cfgs = {
  "devflow": {"commit": {"messagePattern": "^(feat|fix|docs|style|refactor|chore|perf|test): .+", "forbidAiTrailer": True, "forbiddenStaged": ["QA_TOKEN"]},
              "ship": {"branchPattern": "{type}/#{issue}-{slug}", "worktreeDir": ".claude/worktrees", "build": a.get("buildCmd", ""), "mergeMethod": "squash"},
              "_todo": "deploy·local·ops는 서버가 생기면 devflow examples/config.example.json을 보고 채우기"},
  "qaflow": {"label": f"{a['name']} 로컬 서버 + 개발 DB", "_todo": "db.cmd·data.tables·api.suites·env는 qaflow examples/config.example.json 참고"},
  "benchflow": {"resultsDir": "docs/bench", "benchmarks": {}},
}
if a.get("hasUi"):
  cfgs["uiflow"] = {"devices": [], "textSizes": ["large", "extra-extra-extra-large", "accessibility-extra-extra-extra-large"],
                    "checks": [{"name": "빌드·타입 검사", "cmd": a.get("uiCheckCmd", "npx tsc --noEmit")}], "_todo": "devices에 QA 시뮬레이터 udid"}
for name, c in cfgs.items():
    p = os.path.join(H, ".config", name, f"{REPO}.json")
    if os.path.exists(p): done.append(f"건너뜀(이미 있음): ~/.config/{name}/{REPO}.json"); continue
    done.append(f"{'(미리보기) ' if DRY else ''}만듦: ~/.config/{name}/{REPO}.json")
    if not DRY:
        os.makedirs(os.path.dirname(p), exist_ok=True); json.dump(c, open(p, "w"), ensure_ascii=False, indent=2); os.chmod(p, 0o600)
# 첫 페르소나 세트(qaflow): 서비스의 핵심 작업(flows)과 축(경험·데이터 양·기기·맥락)으로 기본 6명 + 확장 6명.
# 시나리오·데이터 픽스처 이름은 자리만 잡아 두고, 화면이 생기면 qaflow 시나리오로 채운다.
flows = a.get("flows") or ["핵심 작업"]
f0, f1 = flows[0], flows[min(1, len(flows) - 1)]
common = ["핵심 정보가 …로 잘리지 않는가", "누를 수 있는 것이 무엇인지 보이는가", "다음에 무엇을 하면 되는지 알 수 있는가"]
def P(id, tier, name, who, goal, device=None, data="기본 데이터", fixtures=None, auth="token", scen=None, judge=None):
    return {"id": id, "tier": tier, "name": name, "who": who, "auth": auth, "device": device or {"textSize": "large"},
            "data": {"fixtures": fixtures or [], "description": data}, "goal": goal, "scenarios": scen or ["TODO-" + id], "judge": (judge or []) + common}
AX5 = "accessibility-extra-extra-extra-large"
personas = [
  P("first-timer", "core", "처음 쓰는 사람", f"{a['name']}을(를) 처음 설치한 사람", f"앱이 하는 일을 알고 첫 {f0}", auth="none", data="로그아웃, 데이터 없음",
    judge=["첫 화면만 보고 앱이 하는 일을 알 수 있는가", "로그인·권한 요청이 이유와 함께 나오는가"]),
  P("heavy-data", "core", "데이터가 많이 쌓인 사람", "오래 써서 기록이 많은 사람", f"많은 기록 중 하나를 찾아 {f1}", data="많음", fixtures=["many-records"],
    judge=["목록이 길어도 원하는 걸 찾을 수 있는가"]),
  P("power-user", "core", "꼼꼼히 다듬는 사람", "세부까지 고치는 숙련 사용자", f"{f1} 결과를 세부까지 고치기", data="보통~많음", fixtures=["detailed-records"]),
  P("large-text", "core", "큰 글자로 쓰는 사람", "글자를 가장 크게 키워 쓰는 사람", f"{f0} → {f1}", device={"textSize": AX5},
    judge=["버튼·아이콘이 그려지고 화면 밖으로 밀리지 않는가"]),
  P("hurried", "core", "하고 바로 나가는 사람", "짧게 쓰고 앱을 떠나는 사람", f"{f0} 후 앱을 떠났다가 나중에 확인",
    judge=["다시 열었을 때 결과와 다음 할 일이 바로 보이는가"]),
  P("dark-calm", "core", "다크 모드·동작 줄이기", "밤에 쓰고 움직임을 줄여 둔 사람", "주요 화면 둘러보기", device={"textSize": "large", "appearance": "dark", "reduceMotion": True},
    judge=["다크 모드 대비가 충분한가", "동작 줄이기에서 깨지는 화면이 없는가"]),
  P("first-large", "extended", "처음 + 큰 글자", "처음 설치한, 글자를 크게 쓰는 사람", "첫 화면에서 로그인까지", auth="none", device={"textSize": AX5}, data="로그아웃"),
  P("heavy-dark", "extended", "많은 데이터 + 다크", "밤에 쌓인 기록을 정리하는 사람", "목록 훑기", device={"textSize": "large", "appearance": "dark"}, fixtures=["many-records"], data="많음"),
  P("power-large", "extended", "숙련 + 큰 글자", "큰 글자로 세부를 고치는 사람", "세부 화면 훑기", device={"textSize": AX5}, fixtures=["detailed-records"], data="보통~많음"),
  P("failed-once", "extended", "실패를 겪은 사람", f"{f0}이(가) 실패했던 사람", "실패 이유와 다음 행동 알기", fixtures=["failed-record"], data="실패 1건",
    judge=["실패가 어디에 어떻게 보이는가", "다시 시도 같은 다음 행동이 있는가"]),
  P("empty-state", "extended", "로그인했지만 비어 있는 사람", "가입만 하고 아직 쓰지 않은 사람", f"빈 화면에서 첫 {f0}", data="로그인, 데이터 없음",
    judge=["빈 상태에 다음 할 일이 안내되는가"]),
  P("settings-calm", "extended", "설정·보조 화면 + 동작 줄이기", "설정을 자주 보는 사람", "설정·보조 화면 둘러보기", device={"textSize": "extra-extra-extra-large", "reduceMotion": True}),
]
pdoc = {"axes": {"경험": ["처음", "익숙함"], "데이터 양": ["없음", "보통", "많음"], "기기": ["보통 글자", "큰 글자", "다크", "동작 줄이기"], "맥락": ["급함", "계획적"], "하려는 일": flows},
        "fixtures": {"many-records": "echo TODO: 테스트 계정에 기록을 많이 만드는 명령(AI 호출 없이)", "detailed-records": "echo TODO", "failed-record": "echo TODO"},
        "personas": personas, "_todo": "scenarios의 TODO-*는 qaflow 시나리오 이름으로, fixtures는 데이터 만드는 명령으로 바꾸기"}
pp = os.path.join(H, ".config", "qaflow", "personas", f"{REPO}.json")
if os.path.exists(pp): done.append(f"건너뜀(이미 있음): ~/.config/qaflow/personas/{REPO}.json")
else:
    done.append(f"{'(미리보기) ' if DRY else ''}만듦: ~/.config/qaflow/personas/{REPO}.json (페르소나 {len(personas)}명: 기본 6 + 확장 6)")
    if not DRY:
        os.makedirs(os.path.dirname(pp), exist_ok=True); json.dump(pdoc, open(pp, "w"), ensure_ascii=False, indent=2)
# 전역 지침: 한국어 답변 규칙이 없으면 추가
g = os.path.join(H, ".claude", "CLAUDE.md"); gc = open(g).read() if os.path.exists(g) else ""
if "한국어" not in gc:
    done.append(f"{'(미리보기) ' if DRY else ''}덧붙임: ~/.claude/CLAUDE.md 한국어 답변 규칙")
    if not DRY:
        os.makedirs(os.path.dirname(g), exist_ok=True)
        open(g, "a").write("\n# 응답 언어 (모든 프로젝트 공통, 예외 없음)\n\n- 사용자에게 보이는 모든 문장은 한국어로 작성한다(최종 요약 포함). 영어로 쓴 뒤 번역하지 않는다. 코드 식별자·명령어·파일 경로만 원문.\n")
print("\n".join(done))
json.dump({"plugin": "startflow", "kind": "init", "title": f"처음 세팅 — {a['name']}", "summary": f"{len(done)}개 항목" + (" (미리보기)" if DRY else ""),
           "env": ROOT, "status": "ok", "sections": [{"heading": "만든 것", "table": {"columns": ["결과"], "rows": [[d] for d in done]}},
           {"heading": "다음 할 일", "text": f"1. 핵심 가정 검증 스크립트부터: {a.get('coreRisk', '')}\n2. 서버가 생기면 devflow deploy·local·ops 설정 채우기\n3. QA 데이터·API가 생기면 qaflow 설정과 페르소나 다듬기\n4. 첫 커밋: chore: 프로젝트 초기 세팅(사용자 확인 후)"}]},
          open(os.environ["REPORT_JSON"], "w"), ensure_ascii=False)
PY
echo "리포트: $(python3 "$DIR/scripts/report_html.py" "$REPORT_JSON")"; rm -f "$REPORT_JSON"
echo "$(date '+%F %T')	init	$ROOT" >> "$HOME/.config/startflow-usage.log" 2>/dev/null || true
