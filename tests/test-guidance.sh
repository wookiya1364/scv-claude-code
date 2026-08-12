#!/usr/bin/env bash
# test-guidance.sh — guidance-ablation phase 1 (promote.md · work.md).
#
# Covers TESTS.md scenarios of 20260807-wookiya1364-guidance-ablation:
#   1. marker integrity — every SCV:GUIDANCE marker in promote.md/work.md is
#      paired and un-nested (lint).
#   2. default-mode invariance — with SCV_GUIDANCE unset (or =full) the
#      injected projection is byte-identical to the protocol source.
#   3. minimal filter — SCV_GUIDANCE=minimal removes every GUIDANCE block
#      (0 guidance lines remain) while ALL CONTRACT lines survive.
#   5. invalid markers fail closed — unclosed / unmatched / nested / malformed
#      markers abort with a clear file:line error, empty stdout, and no file
#      rewritten (no partial injection) — including through
#      tools/materialize-profile.sh, the wrapper injection point.
#   6. the other protocols are untouched by phase 1 — no markers, and (in a
#      git checkout) no diff outside promote.md/work.md.
#   7. deck render never exposes the markers — an md containing markers builds
#      to HTML without the marker text (the guidance BODY still renders: deck
#      is a document render, not an injection).
# (Scenario 4 — full/minimal run equivalence over the run-dry promote·work
#  paths — lives in core/tests/run-dry.sh section [19].)
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STANDARD_ROOT="$HERE/.."
REPO_ROOT="$(cd "$STANDARD_ROOT/.." && pwd)"
FILTER="$STANDARD_ROOT/scripts/guidance-filter.sh"
PROMOTE_CMD="$STANDARD_ROOT/protocols/promote.md"
WORK_CMD="$STANDARD_ROOT/protocols/work.md"
OPEN_MARKER='<!-- SCV:GUIDANCE -->'
CLOSE_MARKER='<!-- /SCV:GUIDANCE -->'

pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if eval "$1"; then ok; else bad "$2"; fi }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$FILTER" ]] && ok || bad "guidance-filter.sh missing or not executable"

# ---- [1] marker integrity (lint) ------------------------------------------
LINT_OUT=$(bash "$FILTER" --lint "$PROMOTE_CMD" "$WORK_CMD" 2>&1)
[[ $? -eq 0 ]] && ok || bad "lint: promote.md/work.md markers unbalanced: $LINT_OUT"
grep -qF -- "GUIDANCE_LINT: OK file=$PROMOTE_CMD" <<< "$LINT_OUT" && ok || bad "lint: no promote.md stats line"
grep -qF -- "GUIDANCE_LINT: OK file=$WORK_CMD" <<< "$LINT_OUT" && ok || bad "lint: no work.md stats line"
# both phase-1 protocols actually carry classified blocks
for f in "$PROMOTE_CMD" "$WORK_CMD"; do
  g=$(sed -n "s|.*file=$f guidance_lines=\([0-9]*\) .*|\1|p" <<< "$LINT_OUT")
  [[ -n "$g" && "$g" -gt 0 ]] && ok || bad "lint: $f reports zero guidance lines (classification missing)"
done

# ---- [2] default-mode invariance ------------------------------------------
bash "$FILTER" "$PROMOTE_CMD" | cmp -s - "$PROMOTE_CMD" && ok || bad "default mode: promote.md projection not byte-identical"
SCV_GUIDANCE=full bash "$FILTER" "$WORK_CMD" | cmp -s - "$WORK_CMD" && ok || bad "full mode: work.md projection not byte-identical"
SCV_GUIDANCE=bogus bash "$FILTER" "$PROMOTE_CMD" >/dev/null 2>"$TMP/bogus.err" \
  && bad "invalid SCV_GUIDANCE value accepted" || ok
grep -q "invalid SCV_GUIDANCE" "$TMP/bogus.err" && ok || bad "invalid mode: unclear error message"

# ---- [3] minimal filter ----------------------------------------------------
SCV_GUIDANCE=minimal bash "$FILTER" "$PROMOTE_CMD" > "$TMP/promote.min.md"
SCV_GUIDANCE=minimal bash "$FILTER" "$WORK_CMD" > "$TMP/work.min.md"
for f in "$TMP/promote.min.md" "$TMP/work.min.md"; do
  grep -qF -- "SCV:GUIDANCE" "$f" && bad "minimal: marker text leaked into $f" || ok
done
# 0 guidance lines remain: minimal line count == lint total - lint guidance
for pair in "$PROMOTE_CMD|$TMP/promote.min.md" "$WORK_CMD|$TMP/work.min.md"; do
  src="${pair%|*}"; min="${pair#*|}"
  g=$(sed -n "s|.*file=$src guidance_lines=\([0-9]*\) .*|\1|p" <<< "$LINT_OUT")
  t=$(sed -n "s|.*file=$src .*total_lines=\([0-9]*\) .*|\1|p" <<< "$LINT_OUT")
  m=$(wc -l < "$min" | tr -d ' ')
  [[ "$m" -eq $((t - g)) ]] && ok || bad "minimal: $src line arithmetic off (min=$m, total=$t, guidance=$g)"
done
# guidance content really gone
for s in "Socratic clarification" "Anti-patterns to avoid" "illustrative only — replace ALL names"; do
  grep -qF -- "$s" "$TMP/promote.min.md" && bad "minimal promote.md: guidance leaked: $s" || ok
done
for s in "Question template (use as-is)" "Recommended migration to Playwright" "3 days (default · recommended)"; do
  grep -qF -- "$s" "$TMP/work.min.md" && bad "minimal work.md: guidance leaked: $s" || ok
done
# the CONTRACT surface fully survives
for s in "promote-helper.sh" "handoff.sh" "deck.sh" "readpath.sh" \
         "status: planned" "raw_sources:" "refs: []" "## How to run" \
         "scv/DECISIONS.md" "<YYYYMMDD>-<AUTHOR>-<slug>" "Never silently overwrite"; do
  grep -qF -- "$s" "$TMP/promote.min.md" && ok || bad "minimal promote.md: contract lost: $s"
done
# Every CONTRACT string that must survive ablation has to be registered here by
# hand: run-dry [19a] only diffs script calls and column-0 frontmatter keys, and
# [19b] never runs an agent — so a contract line wrongly wrapped in GUIDANCE
# markers disappears for minimal users with every other test still green. This
# array is the only detector. Add an anchor whenever work.md gains a CONTRACT line.
for s in "work.sh" "regression.sh" "pr-helper.sh" "deck.sh" "drift-detect.sh" \
         "--archive" "status: obsolete" "obsoleted_at" "ARCHIVED_AT.md" \
         "All tests passed. Archive" "video: 'on'" "scv/DECISIONS.md" \
         "- path delta:" "Step 9b.0 only" \
         "Implementation principles" "reuse what is there" \
         "simplest implementation" "one clear concern" "costly to reverse" \
         "Guardrails override them"; do
  grep -qF -- "$s" "$TMP/work.min.md" && ok || bad "minimal work.md: contract lost: $s"
done

# ---- [5] invalid markers fail closed ---------------------------------------
mk_fixture() { printf '%s\n' "$@" > "$TMP/$1.md.tmp"; }  # unused helper guard
printf '# A\n\n%s\ncoaching\n' "$OPEN_MARKER" > "$TMP/unclosed.md"
printf '# B\n\n%s\ntext\n' "$CLOSE_MARKER" > "$TMP/unmatched.md"
printf '# C\n\n%s\n%s\nx\n%s\n%s\n' "$OPEN_MARKER" "$OPEN_MARKER" "$CLOSE_MARKER" "$CLOSE_MARKER" > "$TMP/nested.md"
printf '# D\n\n%s trailing junk\nx\n%s\n' "$OPEN_MARKER" "$CLOSE_MARKER" > "$TMP/malformed.md"
for fx in unclosed unmatched nested malformed; do
  out=$(SCV_GUIDANCE=minimal bash "$FILTER" "$TMP/$fx.md" 2>"$TMP/$fx.err")
  rc=$?
  [[ $rc -ne 0 ]] && ok || bad "fail-closed: $fx.md accepted (rc=0)"
  [[ -z "$out" ]] && ok || bad "fail-closed: $fx.md produced partial stdout"
  grep -q "$TMP/$fx.md:[0-9]" "$TMP/$fx.err" && ok || bad "fail-closed: $fx.md error lacks file:line"
done
# full mode validates too (injection aborts even when nothing would be stripped)
SCV_GUIDANCE=full bash "$FILTER" "$TMP/unclosed.md" >/dev/null 2>&1 \
  && bad "fail-closed: full mode ignored an unclosed marker" || ok
# --in-place multi-file: a broken sibling means NO file is rewritten
printf '# ok\n\n%s\ncoaching\n%s\nbody\n' "$OPEN_MARKER" "$CLOSE_MARKER" > "$TMP/good.md"
cp "$TMP/good.md" "$TMP/good.orig"
SCV_GUIDANCE=minimal bash "$FILTER" --in-place "$TMP/good.md" "$TMP/unclosed.md" >/dev/null 2>&1 \
  && bad "fail-closed: --in-place with broken sibling exited 0" || ok
cmp -s "$TMP/good.md" "$TMP/good.orig" && ok || bad "fail-closed: --in-place partially rewrote good.md despite broken sibling"

# ---- [5b] wrapper injection point: tools/materialize-profile.sh ------------
MATERIALIZE="$REPO_ROOT/tools/materialize-profile.sh"
VALIDATE="$REPO_ROOT/tools/validate-host-profile.sh"
if [[ -x "$MATERIALIZE" && -x "$VALIDATE" ]]; then
  cat > "$TMP/profile.env" <<'PROFILE'
SCV_HOST_PROFILE_API=1
SCV_HOST_ID=guidance-test
SCV_HOST_LABEL=Guidance Test Host
SCV_ACTION_TEMPLATE=hostcmd-{action}
SCV_ARGUMENT_STYLE=argv-array
SCV_STATE_INDEX=SCV.md
SCV_ROOT_ENV=GUIDANCE_TEST_ROOT
SCV_GRAPH_SKILL_PATHS=/nonexistent/SKILL.md
SCV_UPDATE_OWNER=adapter
SCV_MODEL_POLICY_OWNER=adapter
PROFILE
  mk_core() {  # $1 = target dir
    mkdir -p "$1/protocols" "$1/scripts"
    cp "$STANDARD_ROOT"/protocols/*.md "$1/protocols/"
    cp "$FILTER" "$1/scripts/guidance-filter.sh"
  }
  # default (no SCV_GUIDANCE) → markers + guidance retained in the projection
  mk_core "$TMP/mcore-full"
  env -u SCV_GUIDANCE bash "$MATERIALIZE" --root "$TMP/mcore-full" --profile "$TMP/profile.env" >/dev/null 2>&1 \
    && ok || bad "materialize(default): failed on valid markers"
  grep -qF -- "$OPEN_MARKER" "$TMP/mcore-full/protocols/promote.md" && ok || bad "materialize(default): markers stripped from projection"
  grep -qF -- "Anti-patterns to avoid" "$TMP/mcore-full/protocols/promote.md" && ok || bad "materialize(default): guidance stripped from projection"
  # minimal → guidance gone, contract (host-rendered) kept
  mk_core "$TMP/mcore-min"
  SCV_GUIDANCE=minimal bash "$MATERIALIZE" --root "$TMP/mcore-min" --profile "$TMP/profile.env" >/dev/null 2>&1 \
    && ok || bad "materialize(minimal): failed on valid markers"
  grep -qF -- "SCV:GUIDANCE" "$TMP/mcore-min/protocols/promote.md" && bad "materialize(minimal): marker leaked" || ok
  grep -qF -- "Anti-patterns to avoid" "$TMP/mcore-min/protocols/promote.md" && bad "materialize(minimal): guidance leaked" || ok
  grep -qF -- "scripts/promote-helper.sh" "$TMP/mcore-min/protocols/promote.md" && ok || bad "materialize(minimal): contract script call lost"
  grep -qF -- "hostcmd-promote" "$TMP/mcore-min/protocols/help.md" && ok || bad "materialize(minimal): host action rendering broken"
  # invalid mode value → abort
  mk_core "$TMP/mcore-bogus"
  SCV_GUIDANCE=bogus bash "$MATERIALIZE" --root "$TMP/mcore-bogus" --profile "$TMP/profile.env" >/dev/null 2>&1 \
    && bad "materialize: invalid SCV_GUIDANCE accepted" || ok
  # broken marker in ANY protocol → whole materialization aborts, nothing filtered
  mk_core "$TMP/mcore-broken"
  printf '%s\n' "$OPEN_MARKER" >> "$TMP/mcore-broken/protocols/promote.md"
  SCV_GUIDANCE=minimal bash "$MATERIALIZE" --root "$TMP/mcore-broken" --profile "$TMP/profile.env" >/dev/null 2>&1 \
    && bad "materialize(minimal): broken marker accepted" || ok
  grep -qF -- "$OPEN_MARKER" "$TMP/mcore-broken/protocols/work.md" \
    && ok || bad "materialize(minimal): partial injection — work.md was filtered despite the abort"
else
  echo "  (skip) tools/materialize-profile.sh not present — injection-point checks skipped"
fi

# ---- [6] guidance markers live only where phase 1 put them -----------------
# The marker-leak check is the durable property: only promote.md and work.md are
# marker-annotated, so the ablation filter has exactly two files to reason about.
#
# This section used to also assert `git diff HEAD -- core/protocols/` touched
# nothing but those two. That clause was a scaffold for the in-flight phase-1
# commit and does not survive it: CI always checks out a clean tree, so it could
# never fail there, while locally it failed on every unrelated protocol edit —
# a check that only ever fires on legitimate work. Removed rather than widened;
# the marker scope below is what it was really guarding.
for f in "$STANDARD_ROOT"/protocols/*.md; do
  base="${f##*/}"
  [[ "$base" == "promote.md" || "$base" == "work.md" ]] && continue
  grep -qF -- "SCV:GUIDANCE" "$f" && bad "phase-1 scope: marker leaked into $base" || ok
done

# ---- [7] deck render never exposes the markers -----------------------------
DECKDOC="$STANDARD_ROOT/DeckUI/scripts/deckdoc"
if command -v node >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1 \
  && { [[ -d "$DECKDOC/node_modules" ]] || ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1; }; then
  cat > "$TMP/marked.md" <<MD
# 마커 렌더 확인

## 배경

$OPEN_MARKER
가이던스 본문은 렌더되지만
$CLOSE_MARKER
계약 본문 CONTRACT_SENTINEL
MD
  node "$DECKDOC/doc.mjs" "$TMP/marked.md" --out "$TMP/marked.html" --no-source >/dev/null 2>&1 \
    && ok || bad "deck: build failed on marker-bearing md"
  grep -qF -- "SCV:GUIDANCE" "$TMP/marked.html" && bad "deck: marker text visible in render output" || ok
  grep -qF -- "CONTRACT_SENTINEL" "$TMP/marked.html" && ok || bad "deck: contract body missing from render"
  grep -qF -- "가이던스 본문은 렌더되지만" "$TMP/marked.html" && ok || bad "deck: guidance body should still render (deck ≠ injection)"
else
  echo "  (skip) node/pnpm unavailable — deck marker-exposure check skipped"
fi

echo ""
echo "test-guidance: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
