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
# 전역 지침: 한국어 답변 규칙이 없으면 추가
g = os.path.join(H, ".claude", "CLAUDE.md"); gc = open(g).read() if os.path.exists(g) else ""
if "한국어" not in gc:
    done.append(f"{'(미리보기) ' if DRY else ''}덧붙임: ~/.claude/CLAUDE.md 한국어 답변 규칙")
    if not DRY:
        os.makedirs(os.path.dirname(g), exist_ok=True)
        open(g, "a").write("\n# 응답 언어 (모든 프로젝트 공통, 예외 없음)\n\n- 사용자에게 보이는 모든 문장은 한국어로 작성한다(최종 요약 포함). 영어로 쓴 뒤 번역하지 않는다. 코드 식별자·명령어·파일 경로만 원문.\n")
print("\n".join(done))
PY
echo "$(date '+%F %T')	init	$ROOT" >> "$HOME/.config/startflow-usage.log" 2>/dev/null || true
