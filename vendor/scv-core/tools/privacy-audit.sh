#!/usr/bin/env bash
# privacy-audit.sh — 저장소의 과거 기록 전체(모든 ref 의 파일 · 커밋 메시지 · 작성자)에서 개인정보를 찾는다.
#
#   bash tools/privacy-audit.sh --repos <git 저장소>... [--terms <비밀 목록 파일>] [--emails]
#
# 규칙은 core/scripts/lib/privacy.sh 와 같다(개인 메일 · 내 컴퓨터 경로 · 세션 id · 세션 링크 줄 · 비밀 목록 낱말,
# --emails 일 때만 작성자 noreply · 봇 주소와 개인 메일 주소를 본다, 가짜 시험 자료 · 래퍼 안 Core 사본 · 그림 파일은 건너뜀). 비밀 목록 낱말은 출력에서
# 가린다. 걸린 것이 없으면 "OK privacy-audit: …" 와 exit 0, 있으면 "✖ …" 줄들과 exit 1. python3 가 필요하다.
set -uo pipefail
repos=(); terms=""; emails=off
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) shift; while [[ $# -gt 0 && "$1" != --* ]]; do repos+=("$1"); shift; done ;;
    --terms) terms="${2:-}"; shift 2 || shift ;;
    --emails) emails=on; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "usage: privacy-audit.sh --repos <repo>... [--terms <file>]" >&2; exit 2 ;;
  esac
done
[[ ${#repos[@]} -gt 0 ]] || { echo "usage: privacy-audit.sh --repos <repo>... [--terms <file>]" >&2; exit 2; }
python3 - "$terms" "$emails" "${repos[@]}" <<'PY'
import re, subprocess, sys
terms_file, emails, repos = sys.argv[1], sys.argv[2] == "on", sys.argv[3:]
terms = []
if terms_file:
    terms = [t.strip() for t in open(terms_file, encoding="utf-8") if t.strip() and not t.startswith("#")]
RULES = [
    ("session-line", re.compile(rb"(^|[^A-Za-z])[A-Z][A-Za-z]*-Session:\s|/code/session_[A-Za-z0-9]")),
    ("session-id", re.compile(rb"session_01[A-Za-z0-9]{10,}")),
    ("local-path", re.compile(rb"/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|/private/tmp/claude-[0-9]+")),
    ("personal-email", re.compile(rb"[A-Za-z0-9._%+-]+@(gmail|googlemail|naver|daum|hanmail|kakao|nate|hotmail|outlook|live|yahoo|icloud|me|proton|protonmail)\.[a-z.]+", re.I)),
]
TERMS = [(i + 1, re.compile(rb"(?<![A-Za-z0-9])" + re.escape(t.encode()) + rb"(?![A-Za-z0-9])", re.I)) for i, t in enumerate(terms)]
SKIP = re.compile(r"(^|/)tests/fixtures/|(^|/)vendor/|\.(gif|png|jpe?g|webp|ico|mp4|webm|woff2?|ttf|pdf)$")
OKMAIL = re.compile(r"(@users\.noreply\.github\.com|^noreply@github\.com|^noreply@anthropic\.com)$")
def hits(data):
    out = [n for n, rx in RULES if rx.search(data) and (emails or n != "personal-email")]
    out += ["private term #%d" % i for i, rx in TERMS if rx.search(data)]
    return out
total = 0
for repo in repos:
    found = {}
    def add(k): found[k] = found.get(k, 0) + 1
    refs = [r for r in subprocess.run(["git", "-C", repo, "for-each-ref", "--format=%(refname)", "refs/heads", "refs/tags", "refs/remotes"], capture_output=True, text=True).stdout.split() if not r.endswith("/HEAD")]
    if not refs:
        print("✖ %s: no refs" % repo); total += 1; continue
    log = subprocess.run(["git", "-C", repo, "log", "--format=%H%x00%an%x00%ae%x00%cn%x00%ce%x00%B%x01"] + refs, capture_output=True).stdout
    for rec in log.split(b"\x01"):
        f = rec.strip(b"\n").split(b"\x00")
        if len(f) < 6: continue
        for mail in ((f[2], f[4]) if emails else ()):
            if not OKMAIL.search(mail.decode("utf-8", "replace")): add("author/committer email not noreply")
        for name in ((f[1], f[3]) if emails else ()):
            for h in hits(name): add("author/committer name: " + h)
        for h in hits(f[5]): add("commit message: " + h)
    objs = subprocess.run(["git", "-C", repo, "rev-list", "--objects"] + refs, capture_output=True, text=True).stdout.splitlines()
    paths = {}
    for l in objs:
        p = l.split(" ", 1)
        if len(p) == 2: paths.setdefault(p[0], set()).add(p[1])
    cat = subprocess.Popen(["git", "-C", repo, "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    for sha, ps in paths.items():
        live = [p for p in ps if not SKIP.search(p)]
        if not live: continue
        cat.stdin.write((sha + "\n").encode()); cat.stdin.flush()
        hdr = cat.stdout.readline().split()
        if len(hdr) < 3: continue
        data = cat.stdout.read(int(hdr[2])); cat.stdout.read(1)
        if hdr[1] != b"blob" or b"\0" in data[:8000]: continue
        for h in hits(data):
            for p in live: add("file %s: %s" % (p, h))
    cat.stdin.close()
    for k, v in sorted(found.items()):
        print("✖ %s: %s (%d)" % (repo, k, v))
    total += sum(found.values())
    if not found:
        print("ok %s: %d ref(s) clean" % (repo, len(refs)))
if total:
    sys.exit(1)
print("OK privacy-audit: %d repo(s), %d private term(s)" % (len(repos), len(terms)))
PY
