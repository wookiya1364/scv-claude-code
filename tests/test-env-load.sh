#!/usr/bin/env bash
# test-env-load.sh — env_load 가 설정을 한 번에 읽어도(jq 한 번) 키마다 settings_get 으로 읽은 것과
# 값이 똑같은지 본다. 공백 · $ · 따옴표 · 탭 · 줄바꿈 · 숫자 · true/false/null · 비밀 키 · 환경 우선까지.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../scripts/lib"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-env-load.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
command -v jq >/dev/null 2>&1 || { echo "test-env-load: jq missing — skip"; exit 0; }

mkdir -p "$WORK/p/scv"
jq -n '{
  SCV_LANG: "korean",
  SCV_PR_BASE: "dev $HOME \"quoted\" back\\slash",
  SCV_ATTACHMENTS_RETENTION_DAYS: 7,
  SCV_ALWAYS_ON: true,
  SCV_GRAPH: false,
  SCV_PLAIN_LANGUAGE: null,
  SCV_PR_PLATFORM: "two\tcols",
  NOTIFIER_PROVIDER: "line one\nline two",
  JIRA_BASE_URL: "https://jira.example.test",
  GITLAB_TOKEN: "https://plain-file-token-0000"
}' > "$WORK/p/scv/scv_settings.json"
jq -n '{ GITLAB_TOKEN: "https://secret-file-token-1111", SCV_LANG: "japanese" }' > "$WORK/p/scv/scv_settings.secret.json"

# 기대: 키마다 settings_get(옛 길) · 실제: env_load(새 길) — 같은 껍데기 안에서, 환경 하나를 덧씌운 채로
dump() {  # <mode old|new> → 'KEY=<값의 od>' 줄
  ( cd "$WORK/p" && SCV_PR_BASE_OVERRIDE_TEST=1 SCV_EFFORT_MODE="from-env" bash -c '
      source "$1/settings.sh"; source "$1/env.sh"
      if [[ "$2" == old ]]; then
        for k in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS; do v="$(settings_get "$k")"; [[ -n "$v" ]] && printf "%s=%s\n" "$k" "$(printf "%s" "$v" | od -An -c | tr -s " ")"; done
      else
        env_load 2>/dev/null
        for k in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS; do v="${!k:-}"; [[ -n "$v" ]] && printf "%s=%s\n" "$k" "$(printf "%s" "$v" | od -An -c | tr -s " ")"; done
      fi' _ "$LIB" "$1" 2>/dev/null ) | LC_ALL=C sort
}
old="$(dump old)"; new="$(dump new)"
[[ -n "$old" && "$old" == "$new" ]] && ok "env_load 와 키마다 settings_get 의 값이 바이트까지 같다 ($(grep -c . <<< "$new")개)" \
  || fail "값이 다르다:
$(diff <(printf '%s\n' "$old") <(printf '%s\n' "$new"))"

has() { grep -q "^$1=" <<< "$new" && ok "$2" || fail "$2 — $1 없음"; }
hasnot() { grep -q "^$1=" <<< "$new" && fail "$2 — $1 있음" || ok "$2"; }
grep -q '^SCV_LANG= j a p a n e s e' <<< "$new" && ok "비밀 파일이 일반 파일보다 앞선다(SCV_LANG)" || fail "SCV_LANG 우선순위"
tok="$( cd "$WORK/p" && bash -c 'source "$1/settings.sh"; source "$1/env.sh"; env_load 2>/dev/null; printf "%s" "${GITLAB_TOKEN:-}"' _ "$LIB" )"
[[ "$tok" == "https://secret-file-token-1111" ]] && ok "비밀 키는 비밀 파일 값만" || fail "비밀 키 값: [$tok]"
grep -q '^SCV_EFFORT_MODE= f r o m - e n v' <<< "$new" && ok "환경에 있던 값이 파일보다 앞선다" || fail "환경 우선"
hasnot SCV_GRAPH "false 는 빈 값(settings_lookup_json 과 같음)"
hasnot SCV_PLAIN_LANGUAGE "null 은 빈 값"
grep -q '^NOTIFIER_PROVIDER=.*\\n' <<< "$new" && ok "줄바꿈 값은 그대로(다시 읽기 경로)" || fail "줄바꿈 값"
grep -q '^SCV_PR_PLATFORM=.*\\t' <<< "$new" && ok "탭 값은 그대로(다시 읽기 경로)" || fail "탭 값"

# 비밀 키가 일반 파일에 있으면 알린다 — 값은 찍지 않는다
err="$( cd "$WORK/p" && bash -c 'source "$1/settings.sh"; source "$1/env.sh"; env_load' _ "$LIB" 2>&1 >/dev/null )"
grep -q 'GITLAB_TOKEN is a secret' <<< "$err" && ! grep -q 'plain-file-token-0000' <<< "$err" \
  && ok "일반 파일의 비밀 키는 알리고 값은 찍지 않는다" || fail "비밀 키 알림: $err"

# 순수 조각: 같은 입력 → 같은 출력
J='{"A":"x","B":2,"C":false}'
a="$(bash -c 'source "$1/settings.sh"; settings_lookup_many_json "$2" "A B C D"' _ "$LIB" "$J")"
[[ "$a" == $'A\tx\nB\t2' ]] && ok "settings_lookup_many_json: 있는 키만, false 는 빼고" || fail "lookup_many: [$a]"

echo "test-env-load: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
