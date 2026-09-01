#!/usr/bin/env bash
# scv_autosync — the hook that closes a template-version gap on action start.
#
# The behavior under test is mostly about NOT running: never on a project that
# has not adopted SCV, never on a pre-2.x legacy (its migration deletes user
# docs after a conversation the hook must not skip), never re-entrantly, and
# never fatally. The one time it does run, it must converge in a single pass —
# an autosync that fires on every action is a different bug wearing the
# feature's name.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/scvroot.sh" ]]; then
      CORE="$(cd "$up/$sub" && pwd)"; break 2
    fi
  done
done
[[ -n "$CORE" ]] || { echo "test-autosync: payload not found from $HERE" >&2; exit 1; }
REMOTE_V="$(tr -d '[:space:]' < "$CORE/TEMPLATE_VERSION")"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

stamp_of() { sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$1" | head -n 1; }
set_stamp() {  # set_stamp <SCV.md> <version>
  # perl -pi, not sed -i: BSD sed reads the expression as a backup suffix and
  # dies with "invalid command code" — which took 12 of these cases down on
  # macOS while Linux stayed green, the exact platform split this repo keeps
  # relearning. run-dry.sh already standardized on perl for in-place edits.
  V="$2" perl -pi -e 's|<!-- STANDARD:VERSION -->[^<]*<!-- /STANDARD:VERSION -->|<!-- STANDARD:VERSION -->$ENV{V}<!-- /STANDARD:VERSION -->|' "$1"
}

mk_project() {  # hydrated, committed
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d"
    git init -q . && git config user.email t@e && git config user.name t
    bash "$CORE/scripts/hydrate.sh" init . >/dev/null 2>&1
    git add -A && git commit -qm seed
  ) || { echo "mk_project $1 failed" >&2; exit 1; }
  printf '%s' "$d"
}

# call <project-dir> [env...] — source the lib and invoke the hook the way an
# action script does, capturing stderr (the hook's only reporting channel).
call() {
  local d="$1"; shift
  ( cd "$d" && env "$@" bash -c '
      set -uo pipefail
      source "'"$CORE"'/scripts/lib/scvroot.sh"
      scv_autosync "$(scv_root_dir)"
    ' ) 2>&1 >/dev/null
}

echo "=== T4 — a stale stamp is closed once, then never again ==="
P="$(mk_project conv)"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale )
err="$(call "$P")"
grep -q "refreshed 2.0.0 → $REMOTE_V" <<<"$err" && pass "T4 the gap is reported and closed" \
                                                || fail "T4 no refresh happened" "$err"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T4 the stamp now matches the payload" \
                                                   || fail "T4 the stamp did not converge"
err="$(call "$P")"
grep -q "refreshed" <<<"$err" && fail "T4 a second call refreshed again — no convergence" "$err" \
                              || pass "T4 the second call is a no-op"

echo "=== T4b — a partial refresh is honest: stamp holds, report says PARTIAL, retry converges ==="
P="$(mk_project dirty)"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale && printf '\nlocal note\n' >> scv/PROMOTE.md )
err="$(call "$P")"
grep -q 'local note' "$P/scv/PROMOTE.md" && pass "T4b the uncommitted edit survived" \
                                         || fail "T4b autosync destroyed an uncommitted edit"
grep -q "DIRTY.*PROMOTE.md" <<<"$err" && pass "T4b the skipped file is surfaced on stderr" \
                                      || fail "T4b the refusal was hidden" "$err"
grep -q "PARTIAL" <<<"$err" && pass "T4b the report says PARTIAL, not refreshed" \
                            || fail "T4b a refused run was reported as a full refresh" "$err"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T4b the stamp did not advance past the refusal" \
                                               || fail "T4b the stamp advanced — the refusal would never be retried"
err="$(call "$P")"
grep -q "PARTIAL\|DIRTY" <<<"$err" && pass "T4b the next action retries instead of going silent" \
                                    || fail "T4b the refusal went silent on the second action" "$err"
( cd "$P" && git commit -qam keep >/dev/null 2>&1 )
err="$(call "$P")"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T4b after the user commits, the retry converges" \
                                                   || fail "T4b no convergence after the dirt was committed"

echo "=== T5 — the four cases where it must not run ==="
D="$WORK/unadopted"; mkdir -p "$D/scv"
err="$(call "$D")"
[[ -z "$(ls -A "$D/scv")" ]] && pass "T5 an unadopted project is untouched (no auto-hydrate)" \
                             || fail "T5 autosync populated an empty scv/"

D="$WORK/legacy"; mkdir -p "$D/scv"
printf '# promote convention\n' > "$D/scv/PROMOTE.md"
err="$(call "$D")"
[[ ! -f "$D/scv/SCV.md" ]] && pass "T5 a pre-2.x legacy is not auto-migrated" \
                           || fail "T5 autosync migrated a legacy project without the conversation"
grep -qi "predate\|migration" <<<"$err" && pass "T5 the legacy project gets a pointer line" \
                                        || fail "T5 no pointer for the legacy project" "$err"

P="$(mk_project optout)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
err="$(call "$P" SCV_AUTOSYNC=off)"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T5 SCV_AUTOSYNC=off is honored" \
                                               || fail "T5 the opt-out was ignored"
err="$(call "$P" SCV_AUTOSYNC_RUNNING=1)"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T5 the recursion guard is honored" \
                                               || fail "T5 re-entry ran anyway"

echo "=== T5s — every skip says WHY; a healthy project stays silent ==="
# 조용히 안 되는 것이 진짜 문제였다. 갱신이 필요한데 못 했으면 반드시 말하고,
# 필요 없으면 아무 말도 하지 않는다.
SP="$(mk_project silentskip)"

# (1) 자동 갱신을 껐고 실제로 어긋나 있다 → 알린다
set_stamp "$SP/scv/SCV.md" "2.0.0"; ( cd "$SP" && git commit -qam stale )
err="$(call "$SP" SCV_AUTOSYNC=off)"
grep -q "OUT OF DATE" <<<"$err" && pass "T5s off + out of date is announced" \
                                || fail "T5s the opt-out hid a real gap" "$err"
[[ "$(stamp_of "$SP/scv/SCV.md")" == "2.0.0" ]] && pass "T5s off still changed nothing" \
                                                || fail "T5s off wrote anyway"

# (2) 어긋남이 없으면 껐든 켰든 조용하다 — 매 액션마다 떠들면 금방 무시하게 된다
err="$(call "$SP")"                      # 먼저 맞춘다
err="$(call "$SP" SCV_AUTOSYNC=off)"
[[ -z "$err" ]] && pass "T5s a healthy project is silent even when off" \
                || fail "T5s noise on a healthy project" "$err"

# (3) 배포본이 불완전하면 이름을 대고 말한다 — 예전에는 조용히 넘어갔다
BROKEN="$WORK/brokenpayload"
mkdir -p "$BROKEN/scripts/lib"
cp "$CORE/scripts/lib/scvroot.sh" "$CORE/scripts/lib/template-digest.sh" "$BROKEN/scripts/lib/"
err="$( cd "$SP" && bash -c '
    set -uo pipefail
    source "'"$BROKEN"'/scripts/lib/scvroot.sh"
    scv_autosync "$(scv_root_dir)"
  ' 2>&1 >/dev/null )"
grep -q "payload is incomplete" <<<"$err" && pass "T5s an incomplete payload is named, not skipped" \
                                          || fail "T5s the broken payload went silent" "$err"

echo "=== T5e — a NEWER project stamp is never refreshed backward ==="
# A teammate updates the plugin first; this session still holds the old
# payload. Refreshing "to" the old version would have two machines silently
# reverting each other's templates forever. Caught in the field by a fixture
# stamped 9.9.9 that came back 2.1.0.
P="$(mk_project newer)"
set_stamp "$P/scv/SCV.md" "999.0.0"
( cd "$P" && git commit -qam future )
err="$(call "$P")"
[[ "$(stamp_of "$P/scv/SCV.md")" == "999.0.0" ]] && pass "T5e a newer stamp is left alone" \
                                                 || fail "T5e the project was downgraded to the payload's template"
grep -q "newer than this payload" <<<"$err" && pass "T5e the mismatch is reported, not hidden" \
                                            || fail "T5e no notice about the newer stamp" "$err"

echo "=== T6 — a failed refresh warns and lets the action continue ==="
P="$(mk_project broken)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
chmod 555 "$P/scv"
rc=0; err="$(call "$P")" || rc=$?
chmod 755 "$P/scv"
[[ $rc -eq 0 ]] && pass "T6 the hook exits 0 when sync fails" \
                || fail "T6 a failed refresh broke the caller (rc=$rc)"
grep -q "failed" <<<"$err" && pass "T6 the failure is warned, not swallowed" \
                           || fail "T6 no warning on failure" "$err"

echo "=== T7 — workflow contents are never touched ==="
P="$(mk_project contents)"
mkdir -p "$P/scv/raw" "$P/scv/promote/x" "$P/scv/archive/y" "$P/scv/conversations"
printf 'raw material\n'   > "$P/scv/raw/a.md"
printf 'a plan\n'         > "$P/scv/promote/x/PLAN.md"
printf 'an archive\n'     > "$P/scv/archive/y/PLAN.md"
printf 'a conversation\n' > "$P/scv/conversations/c.md"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git add -A && git commit -qam stale )
# cksum, not md5sum: macOS has no md5sum, and with it missing BOTH sides of
# this comparison became the same xargs error — a false pass that read as
# "byte-identical" while checking nothing.
before="$(cd "$P" && find scv/raw scv/promote scv/archive scv/conversations -type f | sort | xargs cksum)"
call "$P" >/dev/null
after="$(cd "$P" && find scv/raw scv/promote scv/archive scv/conversations -type f | sort | xargs cksum)"
[[ "$before" == "$after" ]] && pass "T7 raw/promote/archive/conversations are byte-identical" \
                            || fail "T7 the automatic refresh modified workflow contents"

echo "=== T8 — an action script carries the hook end to end ==="
# Not just the lib in isolation: status.sh goes through scv_init_paths, so a
# stale project must come back fresh from one ordinary action run.
P="$(mk_project via-action)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
( cd "$P" && bash "$CORE/scripts/status.sh" >/dev/null 2>"$WORK/action-err" ); rc=$?
[[ $rc -eq 0 ]] || fail "T8 status.sh failed (rc=$rc)" "$(cat "$WORK/action-err")"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T8 one ordinary action closed the gap" \
                                                   || fail "T8 the action did not trigger the refresh"
# status.sh spawns readpath.sh several times, and each helper sources this
# library. The process-tree guard must collapse that to ONE check and ONE
# report — N reports per action was the cost bug the review measured.
n="$(grep -c 'scv: workflow docs refreshed' "$WORK/action-err" || true)"
[[ "$n" == "1" ]] && pass "T8 the refresh is checked and reported once per action" \
                  || fail "T8 the action produced $n refresh reports — the process-tree guard leaks"

echo "=== T9 — the refresh is VISIBLE in the turn it happens (v0.42.0) ==="
# 갱신은 예전부터 돌았다. 문제는 훅이 점검의 stderr 를 2>/dev/null 로 버려서
# 갱신됐다는 증거가 화면에 하나도 안 남았다는 것 — 그래서 사용자가 sync 를 손으로
# 한 번 더 쳤다. 여기서 보는 것은 "보이는가" 와 "그 외에는 조용한가" 둘이다.

HOOK="$CORE/template/hooks/on-user-prompt.sh"

hook() {  # hook <project-dir> [env...] — 프롬프트 훅을 돌리고 stdout 만 돌려준다
  local d="$1"; shift
  ( cd "$d" && printf '{"prompt":"hello"}' \
      | env CLAUDE_PLUGIN_ROOT="$CORE" "$@" bash "$HOOK" ) 2>/dev/null
}

# (1) 갱신이 일어난 턴 — 보고가 보이고, 지시 뒤·진단 앞에 있다
P="$(mk_project visible)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
out="$(hook "$P")"
grep -q "workflow docs refreshed" <<<"$out" && pass "T9 the refresh is reported in the turn's own output" \
                                            || fail "T9 the refresh happened silently" "$out"
n_note="$(grep -n 'workflow docs refreshed' <<<"$out" | head -n 1 | cut -d: -f1)"
n_dir="$(grep -n 'SCV: 이 턴의 첫 행동' <<<"$out" | head -n 1 | cut -d: -f1)"
n_diag="$(grep -n 'Current project diagnosis' <<<"$out" | head -n 1 | cut -d: -f1)"
if [[ -n "$n_note" && -n "$n_dir" && -n "$n_diag" && $n_dir -lt $n_note && $n_note -lt $n_diag ]]; then
  pass "T9 the report sits between the directive and the diagnosis"
else
  fail "T9 wrong position (directive=$n_dir report=$n_note diagnosis=$n_diag)"
fi

# (2) 다음 턴은 조용하다 — 갱신할 것이 없으면 한 줄도 늘지 않는다
out="$(hook "$P")"
grep -q '^scv: ' <<<"$out" && fail "T9 a healthy project still emits a report line" "$out" \
                           || pass "T9 a healthy project's turn carries no report at all"

# (3) 갱신과 무관한 stderr 는 새지 않고, 점검이 죽어도 훅은 막지 않는다
FAKE="$WORK/fakecore"; mkdir -p "$FAKE/scripts"
for f in "$CORE"/scripts/*; do ln -s "$f" "$FAKE/scripts/$(basename "$f")" 2>/dev/null || true; done
rm -f "$FAKE/scripts/help.sh"
cat > "$FAKE/scripts/help.sh" <<'STUB'
#!/usr/bin/env bash
echo "scv: settings file created — scv/scv_settings.json (every SCV key)" >&2
echo "ERROR: something unrelated went wrong" >&2
exit 1
STUB
rc=0
out="$( cd "$P" && printf '{"prompt":"hello"}' \
        | env CLAUDE_PLUGIN_ROOT="$FAKE" bash "$HOOK" 2>/dev/null )" || rc=$?
[[ $rc -eq 0 ]] && pass "T9 a failing probe never blocks the turn" \
                || fail "T9 the hook exited $rc when the probe died"
grep -q 'SCV: 이 턴의 첫 행동' <<<"$out" && pass "T9 the directive still goes out without a probe" \
                                          || fail "T9 the directive was lost with the probe" "$out"
grep -q 'settings file created' <<<"$out" && fail "T9 an unrelated scv: report leaked into the turn" "$out" \
                                          || pass "T9 unrelated scv: reports do not leak"
grep -q 'something unrelated' <<<"$out" && fail "T9 raw probe stderr leaked into the turn" "$out" \
                                        || pass "T9 raw probe stderr does not leak"

# (4) 자동 갱신을 껐으면 기존 안내가 그대로 보인다 — 파일은 그대로다
P="$(mk_project offnotice)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
out="$(hook "$P" SCV_AUTOSYNC=off)"
grep -q "OUT OF DATE" <<<"$out" && pass "T9 with autosync off, the gap notice is visible" \
                                || fail "T9 the off-notice never reached the turn" "$out"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T9 off still wrote nothing" \
                                               || fail "T9 off wrote anyway"

# (5) scv 를 채택하지 않은 디렉터리는 아무 말도 하지 않는다
D="$WORK/nohook"; mkdir -p "$D"
rc=0; out="$( cd "$D" && printf '{"prompt":"hello"}' \
              | env CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>/dev/null )" || rc=$?
[[ $rc -eq 0 && -z "$out" ]] && pass "T9 a non-SCV directory produces nothing" \
                             || fail "T9 output or failure outside an SCV project (rc=$rc)" "$out"

echo "=== T9p — the picker keeps template reports and drops everything else ==="
# 고르는 규칙 자체를 직접 본다. 부분 갱신의 본문(DIRTY 줄)은 보고에 붙어 있어야
# 어느 파일이 거부됐는지 알 수 있다.
pick() { ( source "$CORE/scripts/lib/force-help.sh"; scv_force_refresh_note ); }
picked="$(printf '%s\n' \
  'scv: settings file created — scv/scv_settings.json' \
  'scv: template refresh 2.0.0 → 2.3.0 was PARTIAL — the files below were skipped:' \
  '  DIRTY scv/PROMOTE.md' \
  'ERROR: unrelated noise' \
  '  WARN  should not survive a broken chain' \
  'scv: workflow docs refreshed 2.0.0 → 2.3.0 (automatic)' | pick)"
grep -q 'template refresh' <<<"$picked" && pass "T9p a PARTIAL report is kept" \
                                        || fail "T9p the PARTIAL report was dropped" "$picked"
grep -q 'DIRTY scv/PROMOTE.md' <<<"$picked" && pass "T9p the skipped-file body rides along" \
                                             || fail "T9p the DIRTY body was lost" "$picked"
grep -q 'workflow docs refreshed' <<<"$picked" && pass "T9p a refreshed report is kept" \
                                                || fail "T9p the refreshed report was dropped" "$picked"
grep -q 'settings file created' <<<"$picked" && fail "T9p a settings report leaked" "$picked" \
                                             || pass "T9p settings reports are dropped"
grep -q 'unrelated noise' <<<"$picked" && fail "T9p unrelated stderr leaked" "$picked" \
                                       || pass "T9p unrelated stderr is dropped"
grep -q 'should not survive' <<<"$picked" && fail "T9p an orphaned continuation line leaked" "$picked" \
                                          || pass "T9p a continuation line after unrelated text is dropped"
[[ -z "$(printf 'scv: settings file created — x\nplain line\n' | pick)" ]] \
  && pass "T9p nothing to report means no output at all" \
  || fail "T9p the picker spoke when it had nothing to say"

echo "=== T9w — the wrapper docs no longer order a manual sync (skipped if absent) ==="
# 이 저장소 밖이다. 옆에 체크아웃이 있을 때만 돌고, 없으면 건너뛴다.
REPO_ROOT="$(cd "$CORE/.." 2>/dev/null && pwd)"
SIBLINGS="$(cd "$REPO_ROOT/.." 2>/dev/null && pwd || true)"
wrapper_docs=(
  "$SIBLINGS/scv-claude-code/commands/update.md"
  "$SIBLINGS/scv-codex/plugins/scv/README.md"
  "$SIBLINGS/scv-codex/plugins/scv/adapter/protocols/update.md"
)
checked=0
for doc in "${wrapper_docs[@]}"; do
  [[ -f "$doc" ]] || continue
  checked=$((checked+1))
  if grep -qiE 'sync\`? separately' "$doc"; then
    fail "T9w $(basename "$(dirname "$doc")")/$(basename "$doc") still orders a separate sync"
  else
    pass "T9w $(basename "$(dirname "$doc")")/$(basename "$doc") no longer orders a separate sync"
  fi
done
[[ $checked -eq 0 ]] && echo "  – T9w SKIP (no wrapper checkout beside this repo)"

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
