#!/usr/bin/env bash
# test-obsolete-mark.sh — 폐기 표시가 한 곳(scripts/obsolete-mark.sh)에서 세 칸만 바꾸고 보관 목록을 바로 새로 만드는지 본다.
#
# T1 세 칸만 바뀐다 · T2 이미 폐기면 그대로 · T3 스크립트가 목록을 바로 새로 만든다 · T4 work 9c · regression 이 스크립트를 부른다.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/obsolete.sh
source "$CORE/scripts/lib/obsolete.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# T1 — 세 칸만
printf -- '---\ntitle: a\nstatus: done\nkind: feature\nepic: e1\n---\n# a\n\nbody line\n' > "$WORK/p1.md"
scv_obsolete_frontmatter "$(cat "$WORK/p1.md"; printf x)" 2026-11-02 new-x > "$WORK/p1.out"
sed -i.bak '$ s/x$//' "$WORK/p1.out" && rm -f "$WORK/p1.out.bak"
changed="$(diff "$WORK/p1.md" "$WORK/p1.out" | grep -c '^[<>]' || true)"
if grep -qx 'status: obsolete' "$WORK/p1.out" && grep -qx 'obsoleted_at: 2026-11-02' "$WORK/p1.out" \
   && grep -qx 'obsoleted_by: new-x' "$WORK/p1.out" && [[ "$changed" == 4 ]] \
   && [[ "$(sed -n '/^# a$/,$p' "$WORK/p1.md")" == "$(sed -n '/^# a$/,$p' "$WORK/p1.out")" ]]; then
  ok "T1 only the three fields change (1 line out, 3 in), body identical"
else bad "T1 changed lines=$changed"; diff "$WORK/p1.md" "$WORK/p1.out" | sed 's/^/    /' >&2; fi

# T2 — 이미 폐기면 그대로(날짜 덮어쓰기 없음)
t2=$'---\nstatus: obsolete\nobsoleted_at: 2026-10-01\nobsoleted_by: old\n---\n# b\n'
[[ "$(scv_obsolete_frontmatter "$t2" 2026-11-02 new-x; printf x)" == "${t2}x" ]] \
  && ok "T2 an already-obsolete plan comes back byte-identical" || bad "T2 already-obsolete plan was rewritten"

# T3 — 스크립트: 고치고 목록을 바로 새로 만든다
A="$WORK/archive"; mkdir -p "$A/x1" "$A/x2"
printf -- '---\ntitle: x1\nstatus: done\n---\n# x1\n' > "$A/x1/PLAN.md"
printf -- '---\ntitle: x2\nstatus: done\n---\n# x2\n' > "$A/x2/PLAN.md"
printf 'tests stay\n' > "$A/x1/TESTS.md"; cp "$A/x1/TESTS.md" "$WORK/tests.before"
rc=0; out="$(ARCHIVE_DIR="$A" bash "$CORE/scripts/obsolete-mark.sh" x1 new-x 2026-11-02 2>&1)" || rc=$?
s1="$(awk '/slug: x1$/{f=1;next} /slug:/{f=0} f&&/status:/{print $2}' "$A/INDEX.yaml")"
b1="$(awk '/slug: x1$/{f=1;next} /slug:/{f=0} f&&/obsoleted_by:/{print $2}' "$A/INDEX.yaml")"
s2="$(awk '/slug: x2$/{f=1;next} /slug:/{f=0} f&&/status:/{print $2}' "$A/INDEX.yaml")"
if [[ "$rc" == 0 && "$s1" == obsolete && "$b1" == new-x && "$s2" == done && "$out" == *"MARKED: x1"* ]] && cmp -s "$A/x1/TESTS.md" "$WORK/tests.before"; then
  ok "T3 index shows x1 obsolete (by new-x) at once, x2 still done, TESTS.md untouched"
else bad "T3 rc=$rc x1=$s1/$b1 x2=$s2 out=$out"; fi
out2="$(ARCHIVE_DIR="$A" bash "$CORE/scripts/obsolete-mark.sh" x1 other 2026-12-01 2>&1)"
[[ "$out2" == *"ALREADY: x1"* ]] && grep -qx 'obsoleted_at: 2026-11-02' "$A/x1/PLAN.md" \
  && ok "T3 marking twice keeps the first date" || bad "T3 second mark: $out2"

# T4 — 규약 두 곳이 스크립트를 부르고, 손으로 고치는 줄은 없다
w="$CORE/protocols/work.md"; r="$CORE/protocols/regression.md"
if grep -q 'obsolete-mark.sh <B-slug> <A-slug>' "$w" && grep -q 'obsolete-mark.sh <slug> manual' "$r" \
   && ! grep -q '`status: done` → `status: obsolete`' "$w" && ! grep -q '`status: done` → `status: obsolete`' "$r"; then
  ok "T4 work 9c and regression both call the script, no hand edit left"
else bad "T4 protocols still edit by hand or miss the script"; fi

(( fail )) && exit 1
echo "obsolete-mark: all checks passed"
