#!/usr/bin/env bash
# test-hook-dedupe.sh — 매 턴 훅이 같은 판단을 한 번만 하고(사람 메시지 판별 · 선택 창 상태), 설정 파일은
# 한 프로세스에서 jq 한 번으로 펼쳐 읽는지 본다. 결과는 옛 길과 바이트까지 같아야 한다:
#   - settings_get 값 · 경고 = 키마다 settings_lookup_json 으로 읽던 옛 settings_get (모든 키, 이상한 값 포함)
#   - show-real.sh line 에 값을 넘긴 출력 = 넘기지 않고 스스로 구한 출력
#   - 훅 출력 안에 이어서 = choice-gate.sh line + show-real.sh line(스스로 구한 것)
#   - 훅이 부르는 model-prompting.sh kind 1번, choice-gate.sh 1번
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
LIB="$CORE/scripts/lib"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-hook-dedupe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
command -v jq >/dev/null 2>&1 || { echo "test-hook-dedupe: jq missing — skip"; exit 0; }
REAL_JQ="$(command -v jq)"

# ---------------------------------------------------------------- 설정 값: 새 길 = 옛 길
# 옛 settings_get — 이 계획 전의 본문 그대로(키마다 settings_lookup_json). 기대값을 만드는 데만 쓴다.
OLD_GET='
old_get() {
  local key="${1:-}" default="${2:-}"
  [[ -n "$key" ]] || return 0
  local from_env="${!key:-}" from_secret="" from_plain="" plain_json secret_json
  plain_json="$(_settings_slurp "$SCV_SETTINGS_FILE")"
  secret_json="$(_settings_slurp "$SCV_SETTINGS_SECRET_FILE")"
  if [[ -n "$plain_json" || -n "$secret_json" ]]; then
    from_secret="$(settings_lookup_json "$secret_json" "$key")"
    if settings_is_secret "$key"; then
      if [[ -n "$(settings_lookup_json "$plain_json" "$key")" ]]; then
        echo "scv: $key is a secret and must not live in $SCV_SETTINGS_FILE (that file is committed) — the value was IGNORED; move it to $SCV_SETTINGS_SECRET_FILE." >&2
      fi
    else
      from_plain="$(settings_lookup_json "$plain_json" "$key")"
    fi
  fi
  settings_resolve "$from_env" "$from_secret" "$from_plain" "$default"
}'
dump_settings() {  # <dir> <old|new> → 키마다 '[키]=값|' (표준오류도 함께)
  ( cd "$1" && bash -c '
      source "$1/settings.sh"; eval "$3"
      f=settings_get; [[ "$2" == old ]] && f=old_get
      [[ "$2" == new ]] && settings_preload
      for k in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS SCV_SHOW_REAL SCV_CHOICE_GATE n arr obj NOPE; do
        printf "[%s]=" "$k"; v="$($f "$k" dflt)"; printf "%s|\n" "$v"
      done
      SCV_LANG=fromenv; printf "[env]=%s|\n" "$($f SCV_LANG)"' _ "$LIB" "$2" "$OLD_GET" 2>&1 )
}
n=0
for case in \
  'basic|{"SCV_LANG":"korean","SCV_PR_BASE":"dev $HOME \"q\" back\\slash","SCV_ATTACHMENTS_RETENTION_DAYS":7}|-' \
  'types|{"SCV_ALWAYS_ON":true,"SCV_GRAPH":false,"SCV_PLAIN_LANGUAGE":null,"n":0,"arr":[1,2],"obj":{"a":1},"SCV_LANG":""}|-' \
  'ctrl|{"SCV_PR_PLATFORM":"two\tcols","NOTIFIER_PROVIDER":"line one\nline two","SCV_LANG":"cr\r","SCV_DIR":"trail\n\n"}|-' \
  'secret|{"GITLAB_TOKEN":"plain-file-token-0000","SCV_LANG":"korean"}|{"GITLAB_TOKEN":"secret-file-token-1111","SCV_LANG":"japanese"}' \
  'multi|{"SCV_LANG":"korean"} {"SCV_LANG":"english","SCV_SHOW_REAL":"off"}|-' \
  'broken|{"SCV_LANG":|-' \
  'array|[1,2,3]|-' \
  'none|-|-'; do
  name="${case%%|*}"; rest="${case#*|}"; plain="${rest%%|*}"; secret="${rest#*|}"
  d="$WORK/s-$name"; mkdir -p "$d/scv"
  [[ "$plain" == "-" ]] || printf '%s\n' "$plain" > "$d/scv/scv_settings.json"
  [[ "$secret" == "-" ]] || printf '%s\n' "$secret" > "$d/scv/scv_settings.secret.json"
  old="$(dump_settings "$d" old)"; new="$(dump_settings "$d" new)"
  if [[ "$old" == "$new" ]]; then n=$((n + 1)); else fail "설정 값이 옛 길과 다르다 ($name):
$(diff <(printf '%s\n' "$old") <(printf '%s\n' "$new") | head -8)"; fi
  if grep -q 'secret-file-token-1111\|plain-file-token-0000' <<< "$(cd "$d" && bash -c 'source "$1/settings.sh"; settings_get GITLAB_TOKEN >/dev/null' _ "$LIB" 2>&1)"; then
    fail "비밀 값이 경고에 찍혔다 ($name)"
  fi
done
[[ "$n" == 8 ]] && ok "settings_get 값 · 경고가 옛 길과 바이트까지 같다 (견본 8개 × 키 전부)"

# ---------------------------------------------------------------- 설정 파일 하나 = jq 한 번
mkdir -p "$WORK/shim"; printf '#!/bin/sh\necho jq >> "%s"\nexec "%s" "$@"\n' "$WORK/jq.count" "$REAL_JQ" > "$WORK/shim/jq"; chmod +x "$WORK/shim/jq"
: > "$WORK/jq.count"
( cd "$WORK/s-secret" && PATH="$WORK/shim:$PATH" bash -c '
    source "$1/settings.sh"; settings_preload
    for k in SCV_LANG SCV_PR_BASE SCV_GRAPH SCV_DIR GITLAB_TOKEN SCV_SHOW_REAL SCV_CHOICE_GATE SCV_DREAMS SCV_ALWAYS_ON PROJECT_NAME; do
      v="$(settings_get "$k")"
    done' _ "$LIB" >/dev/null 2>&1 )
c="$(grep -c . "$WORK/jq.count")"
[[ "$c" -le 2 ]] && ok "설정 10번 읽기에 jq ${c}번 (파일 둘 — 일반 · 비밀)" || fail "jq ${c}번 — 파일당 한 번이어야 한다"
: > "$WORK/jq.count"
( cd "$WORK/s-secret" && PATH="$WORK/shim:$PATH" bash -c '
    source "$1/settings.sh"; settings_preload
    printf "%s\n" "{\"SCV_LANG\":\"changed\"}" > scv/scv_settings.secret.json
    v="$(settings_get SCV_LANG)"; printf "%s" "$v" > ../changed.out' _ "$LIB" >/dev/null 2>&1 )
[[ "$(cat "$WORK/changed.out" 2>/dev/null)" == "changed" ]] && ok "파일이 바뀌면 표를 새로 만든다 (옛 값을 쓰지 않음)" || fail "바뀐 파일 값: $(cat "$WORK/changed.out" 2>/dev/null)"

# ---------------------------------------------------------------- 같은 판단은 한 번 (훅)
# 코어 사본의 두 스크립트 맨 앞에 부른 횟수를 남기는 줄을 넣어 센다.
mkdir -p "$WORK/core"; cp -R "$CORE/scripts" "$CORE/template" "$WORK/core/"
for s in model-prompting.sh choice-gate.sh; do
  awk -v f="$WORK/calls" -v n="$s" 'NR == 1 { print; print "echo \"" n " ${1:-}\" >> \"" f "\""; next } { print }' \
    "$CORE/scripts/$s" > "$WORK/core/scripts/$s"
done
mkdir -p "$WORK/p/scv"; ( cd "$WORK/p" && git init -q . 2>/dev/null ); printf '{"SCV_LANG":"korean"}\n' > "$WORK/p/scv/scv_settings.json"
IN='{"session_id":"s-dedupe","prompt":"hello","hook_event_name":"UserPromptSubmit"}'
: > "$WORK/calls"
( cd "$WORK/p" && printf '%s' "$IN" | SCV_CHOICE_TOOL=PickTool CLAUDE_PLUGIN_ROOT="$WORK/core" \
    bash "$WORK/core/template/hooks/on-user-prompt.sh" > "$WORK/hook.out" 2>/dev/null )
k="$(grep -c '^model-prompting.sh kind$' "$WORK/calls")"; g="$(grep -c '^choice-gate.sh ' "$WORK/calls")"
[[ "$k" == 1 ]] && ok "사람 메시지 판별(kind)을 한 턴에 한 번" || fail "kind ${k}번"
[[ "$g" == 1 ]] && ok "선택 창 상태(choice-gate)를 한 턴에 한 번" || fail "choice-gate ${g}번: $(grep '^choice-gate' "$WORK/calls" | tr '\n' ' ')"

# ---------------------------------------------------------------- 넘긴 값 = 스스로 구한 값
for host in "" "SCV_CHOICE_TOOL=PickTool" "SCV_CHOICE_TOOL=PickTool SCV_CHOICE_OFF_WHEN=SCV_T_HL=1 SCV_T_HL=1" \
            "SCV_CHOICE_TOOL=PickTool SCV_AUTO_PROMPT_TAGS=task-notification"; do
  for in in "$IN" '{"prompt":"<task-notification>x</task-notification>"}' ''; do
    # shellcheck disable=SC2086
    self="$(cd "$WORK/p" && env $host bash -c '
        cg="$(bash "$1/choice-gate.sh" line 2>/dev/null; printf x)"; printf "%s" "${cg%x}"
        printf "%s" "$2" | bash "$1/show-real.sh" line 2>/dev/null; printf x' _ "$CORE/scripts" "$in")"
    # shellcheck disable=SC2086
    hook="$(cd "$WORK/p" && printf '%s' "$in" | env $host CLAUDE_PLUGIN_ROOT="$CORE" bash "$CORE/template/hooks/on-user-prompt.sh" 2>/dev/null; printf x)"
    self="${self%x}"
    if [[ -n "$self" && "$hook" == *"$self"* ]]; then n=$((n + 1)); else fail "훅 출력에 선택 창 줄 + 스스로 구한 안내가 이어서 들어 있지 않다 (host=[${host}] in=[${in:0:30}])"; fi
  done
done
[[ "$n" == 20 ]] && ok "훅 출력 안 = 선택 창 줄 + 스스로 구한 실체 보여 주기 안내 (호스트 4 × 입력 3)"

echo "test-hook-dedupe: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]]
