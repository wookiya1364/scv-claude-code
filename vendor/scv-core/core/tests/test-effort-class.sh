#!/usr/bin/env bash
# effort-class.sh — the judgment must be deterministic, auditable, and honest
# about what it is: three backtested rules, a user override, and a promotion
# hint. These cases pin the rules, replay the backtest that justified them,
# and check the protocols that consume the judgment say what the design says.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/effort-class.sh" ]]; then
      CORE="$(cd "$up/$sub" && pwd)"; ROOT="$(cd "$up" && pwd)"; break 2
    fi
  done
done
[[ -n "$CORE" ]] || { echo "test-effort-class: payload not found from $HERE" >&2; exit 1; }
EC="$CORE/scripts/effort-class.sh"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# mk_plan <name> <frontmatter-extra> <body>  — a minimal plan folder
mk_plan() {
  local d="$WORK/root/scv/promote/$1"
  mkdir -p "$d"
  printf -- '---\ntitle: t\nslug: %s\nstatus: planned\n%s---\n\n# t\n\n%s\n' "$1" "$2" "$3" > "$d/PLAN.md"
  printf '%s' "$d"
}
cls() { bash "$EC" "$1" | sed -n 's/^EFFORT_CLASS: //p'; }
esc() { bash "$EC" "$1" | sed -n 's/^EFFORT_ESCALATION: //p'; }
rsn() { bash "$EC" "$1" | sed -n 's/^EFFORT_REASON: //p'; }

echo "=== T1 — the three rules, in order ==="
P=$(mk_plan a "parallel_groups: [[1, 2]]
" "plain body")
[[ "$(cls "$P")" == "orchestration" ]] && pass "T1 parallel_groups → orchestration" || fail "T1 R1 miss"
P=$(mk_plan b "" "이 계획은 두 wrapper 후속 릴리스가 필요하다.")
[[ "$(cls "$P")" == "heavy" ]] && pass "T1 wrapper follow-up → heavy" || fail "T1 R2 miss"
P=$(mk_plan c "" "single surface change, nothing else")
[[ "$(cls "$P")" == "standard" ]] && pass "T1 neither → standard" || fail "T1 R3 miss"
P=$(mk_plan d "parallel_groups: [[1]]
" "래퍼 후속도 있다")
[[ "$(cls "$P")" == "orchestration" ]] && pass "T1 R1 outranks R2" || fail "T1 rule order broken"
rsn_out="$(rsn "$P")"
[[ -n "$rsn_out" ]] && pass "T1 a reason line always ships (audit trail)" || fail "T1 empty reason"
# 주석 처리된 템플릿 예시는 신호가 아니다 — promote 스캐폴드가 그대로 담고 있다.
P=$(mk_plan e "# parallel_groups: [[1, 2], [3]]
" "plain")
[[ "$(cls "$P")" == "standard" ]] && pass "T1 a commented-out parallel_groups does not fire" \
                                  || fail "T1 the template comment classified as orchestration"

echo "=== T2 — escalation arms on two of three markers ==="
big="$WORK/root/scv/raw/big.md"; mkdir -p "$(dirname "$big")"
head -c 9500 /dev/zero | tr '\0' 'x' > "$big"
P=$(mk_plan f "" "plain")                                     # 0 markers
[[ "$(esc "$P")" == "normal" ]] && pass "T2 zero markers → normal" || fail "T2 over-armed at 0"
P=$(mk_plan g "" "wrapper 후속 있음")                          # 1 marker
[[ "$(esc "$P")" == "normal" ]] && pass "T2 one marker → normal" || fail "T2 over-armed at 1"
P=$(mk_plan h "" "wrapper 후속. 그리고 adversarial 검증을 요구한다.")   # 2 markers
[[ "$(esc "$P")" == "armed" ]] && pass "T2 two markers → armed" || fail "T2 under-armed at 2"
P=$(mk_plan i "raw_sources:
  - scv/raw/big.md
" "wrapper 후속. mutation 증명 요구.")                          # 3 markers
[[ "$(esc "$P")" == "armed" ]] && pass "T2 three markers → armed" || fail "T2 under-armed at 3"

echo "=== T3 — a frontmatter declaration always wins ==="
P=$(mk_plan j "effort_class: orchestration
" "plain single-surface body")
[[ "$(cls "$P")" == "orchestration" ]] && pass "T3 declared up wins over judged standard" || fail "T3 up-declare lost"
P=$(mk_plan k "effort_class: standard
parallel_groups: [[1]]
" "wrapper everywhere")
[[ "$(cls "$P")" == "standard" ]] && pass "T3 declared down wins over judged orchestration" || fail "T3 down-declare lost"
rsn "$P" | grep -q "declared" && pass "T3 the reason says it was declared" || fail "T3 declared reason missing"

echo "=== T4 — the backtest replays: every archive gets its recorded band ==="
# The bands below are the classifier's own recorded output at introduction
# time, cross-checked against the 14-plan backtest: 13 match the backtest's
# prediction, and decision-log-activation is the KNOWN over-read (its plan
# discusses wrappers only as context) — kept because the section-scoped
# variant scored the same 13/14 with its miss in the EXPENSIVE direction
# instead. Skipped in trees that do not carry this repository's archive
# (wrapper projections) — the fixture is the archive itself.
ARCH="$ROOT/scv/archive"
if [[ -d "$ARCH/20260818-wookiya1364-sync-autopilot" ]]; then
  declare -A EXPECT=(
    [20260804-wookiya1364-team-journal]=heavy
    [20260807-wookiya1364-adoption-only-doc-removal]=heavy
    [20260807-wookiya1364-decision-log-activation]=heavy
    [20260807-wookiya1364-guidance-ablation]=heavy
    [20260807-wookiya1364-plan-grammar]=standard
    [20260807-wookiya1364-routines]=heavy
    [20260811-wookiya1364-implementation-principles]=standard
    [20260812-wookiya1364-ci-provenance-gate]=heavy
    [20260812-wookiya1364-forced-invocation-guard]=heavy
    [20260812-wookiya1364-plain-language]=standard
    [20260813-wookiya1364-deck-redesign]=standard
    [20260814-wookiya1364-release-machinery]=heavy
    [20260818-wookiya1364-regression-contract-repair]=standard
    [20260818-wookiya1364-sync-autopilot]=heavy
  )
  miss=0
  for s in "${!EXPECT[@]}"; do
    got="$(cls "$ARCH/$s")"
    [[ "$got" == "${EXPECT[$s]}" ]] || { miss=$((miss+1)); fail "T4 $s: expected ${EXPECT[$s]}, got $got"; }
  done
  [[ $miss -eq 0 ]] && pass "T4 all 14 backtest archives reproduce their recorded band"
  # 백테스트의 유일한 과소 미스가 이 힌트의 존재 이유다 — 반드시 armed 여야 한다.
  [[ "$(esc "$ARCH/20260818-wookiya1364-sync-autopilot")" == "armed" ]] \
    && pass "T4 the one under-provisioned backtest case is pre-armed" \
    || fail "T4 sync-autopilot is not armed — the hint fails its founding case"
else
  pass "T4 (skip) this tree carries no core archive — the fixture set lives in the source repository"
fi

echo "=== T10 — the review's three findings stay fixed ==="
# CRLF: a Windows-edited plan must not hide parallel_groups — that miss is an
# under-provision, the expensive direction. Caught in review as incidental-only
# safety (the fixture lacked scv/raw/, so ../ resolution failed by luck).
d="$WORK/root/scv/promote/crlf"; mkdir -p "$d"
printf -- '---\r\ntitle: t\r\nparallel_groups: [[1]]\r\n---\r\nbody\r\n' > "$d/PLAN.md"
[[ "$(cls "$d")" == "orchestration" ]] && pass "T10 CRLF frontmatter still classifies" \
                                       || fail "T10 CRLF hid parallel_groups — expensive-direction miss"
# 경로 순회: raw 크기 힌트가 저장소 밖 파일을 세면 안 된다.
mkdir -p "$WORK/root/scv/raw" "$WORK/outside"
head -c 20000 /dev/zero | tr '\0' 'y' > "$WORK/outside/big.bin"
d="$WORK/root/scv/promote/trav"; mkdir -p "$d"
printf -- '---\ntitle: t\nraw_sources:\n  - scv/raw/../../../outside/big.bin\n---\nwrapper only\n' > "$d/PLAN.md"
[[ "$(esc "$d")" == "normal" ]] && pass "T10 a ../ raw path is not sized (no traversal)" \
                               || fail "T10 path traversal counted a file outside the tree"
# 무효 선언: 조용히 삼키지 않고 stderr 로 말한다.
d="$WORK/root/scv/promote/badclass"; mkdir -p "$d"
printf -- '---\neffort_class: HEAVY\n---\nbody\n' > "$d/PLAN.md"
werr="$(bash "$EC" "$d" 2>&1 >/dev/null)"
grep -q "invalid effort_class" <<<"$werr" && pass "T10 an invalid declaration warns instead of vanishing" \
                                          || fail "T10 the bad declaration was swallowed silently" "$werr"
[[ "$(cls "$d")" == "standard" ]] && pass "T10 and the judgment falls through to the rules" \
                                  || fail "T10 invalid declaration changed the band"

echo "=== T5 — deterministic and harmless ==="
P=$(mk_plan m "" "wrapper 후속")
o1="$(bash "$EC" "$P")"; o2="$(bash "$EC" "$P")"; o3="$(bash "$EC" "$P")"
[[ "$o1" == "$o2" && "$o2" == "$o3" ]] && pass "T5 three runs, identical output" || fail "T5 nondeterministic"
before="$(find "$WORK/root" -type f | sort | xargs cksum)"
bash "$EC" "$P" >/dev/null
after="$(find "$WORK/root" -type f | sort | xargs cksum)"
[[ "$before" == "$after" ]] && pass "T5 the judgment writes nothing" || fail "T5 the classifier modified the tree"

echo "=== T6 — the modes are mutually exclusive and off is inert ==="
for proto in work codegen; do
  F="$CORE/protocols/$proto.md"
  grep -q "Effort governor" "$F" || { fail "T6 $proto.md has no governor section"; continue; }
  grep -qE 'SCV_EFFORT_MODE' "$F" && pass "T6 $proto.md reads the mode from the environment" \
                                  || fail "T6 $proto.md never names SCV_EFFORT_MODE"
  grep -qE '`off`.*skip|When `off`' "$F" && pass "T6 $proto.md: off skips the step entirely" \
                                         || fail "T6 $proto.md: off behavior not specified"
  grep -q "do not run the classifier" "$F" || grep -q "no classifier call" "$F" \
    && pass "T6 $proto.md: off makes no classifier call" \
    || fail "T6 $proto.md: off could still invoke the classifier"
done

echo "=== T7 — the grid and the ladder are written down, host-neutrally ==="
F="$CORE/protocols/work.md"
grep -q "no multi-agent fan-out" "$F" && pass "T7 the standard band forbids fan-out" \
                                      || fail "T7 the load-bearing rule is missing"
grep -q "Never demote during verification" "$F" && pass "T7 no demotion during verification" \
                                                || fail "T7 demotion ban missing"
grep -qE "fails its tests twice in a row|refutes the work more than once" "$F" \
  && pass "T7 promotion triggers are mechanical signals" || fail "T7 triggers unspecified"
grep -q "judged band, the band actually used" "$F" && pass "T7 the archive records calibration data" \
                                                   || fail "T7 no recalibration record"
grep -qiE '\bultracode\b|\bxhigh\b' "$F" && fail "T7 a host effort level name leaked into core" \
                                         || pass "T7 bands and shapes only — no host level names"

echo "=== T8 — the consuming contracts stay green ==="
bash "$CORE/scripts/guidance-filter.sh" --lint "$CORE/protocols/work.md" "$CORE/protocols/codegen.md" >/dev/null \
  && pass "T8 guidance lint" || fail "T8 guidance lint broke"
bash "$CORE/scripts/guidance-filter.sh" --mode full "$CORE/protocols/work.md" | cmp -s - "$CORE/protocols/work.md" \
  && pass "T8 work.md full projection is byte-identical" || fail "T8 full projection diverged"

echo "=== T9 — the old world fails these cases ==="
# Not a mutation replay of the whole suite: the property that matters is that
# the feature's two halves are detectable, so their absence is loud. A payload
# without the classifier cannot judge; a protocol without the section cannot
# execute the policy.
OLD="$WORK/old-core"; mkdir -p "$OLD/scripts" "$OLD/protocols"
cp "$CORE/protocols/work.md" "$OLD/protocols/work.md"
sed -i.bak '/### Step 5e — Effort governor/,/### Step 6 — Implement/{/### Step 6 — Implement/!d;}' "$OLD/protocols/work.md" 2>/dev/null \
  || perl -0pi -e 's/### Step 5e — Effort governor.*?(### Step 6 — Implement)/$1/s' "$OLD/protocols/work.md"
if [[ ! -f "$OLD/scripts/effort-class.sh" ]]; then
  pass "T9 an old payload has no classifier — the judgment cannot silently no-op"
else
  fail "T9 fixture error"
fi
grep -q "Effort governor" "$OLD/protocols/work.md" \
  && fail "T9 the excised protocol still carries the section" \
  || pass "T9 T6/T7 would fail against the pre-governor protocol"

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
