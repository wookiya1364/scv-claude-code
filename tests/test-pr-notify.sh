#!/usr/bin/env bash
# test-pr-notify.sh — PR 을 만들면 증적이 Slack 에도 간다 (pr-evidence-notify).
#
# CI 는 실패만 증적, pr-helper 는 PR 본문에만 첨부 — Slack 에 성공 slug 증적을
# 올리는 주체가 없었다 (ai_tm_center 실측). PR 생성/갱신 성공 후, 알림 채널이
# 설정된 프로젝트에서는 같은 증적 목록을 채널에 게시한다. 최선 노력 — 어떤
# 실패도 PR 을 막지 않는다.
#
# Covers TESTS.md T1–T5 of 20260825-wookiya1364-pr-evidence-notify.
#
# Run: bash core/tests/test-pr-notify.sh
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
PRH="$CORE/scripts/pr-helper.sh"
RUNNER="$CORE/scripts/run-plan-tests.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SLUG="20260825-tester-notify-feature"

# 가짜 gh: pr list 는 빈 목록(생성 경로), pr create 는 URL
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "pr list")   ;;
  "pr create") echo "https://example.invalid/pull/5" ;;
  *)           exit 0 ;;
esac
FAKE
chmod +x "$WORK/bin/gh"

# 프로젝트 준비: <base>/prj-<name> 에 저장소 + 계획 + 증적 + 실행 기록
make_proj() {
  local name="$1"
  local P="$WORK/prj-$name"
  mkdir -p "$P/scv/archive/$SLUG"
  ( cd "$P" && git init -q && git config user.name t && git config user.email t@x \
    && git checkout -q -b feat/n && git remote add origin https://github.com/example/repo.git )
  cat > "$P/scv/archive/$SLUG/PLAN.md" <<PLAN
---
title: notify feature
slug: $SLUG
author: tester
created_at: 2026-08-25
status: done
kind: feature
lang: english
---

# notify

## Summary

n.
PLAN
  printf '# Test Plan\n\n## How to run\n\n```bash\ntrue\n```\n\n## Pass criteria\n\n- exit 0\n' > "$P/scv/archive/$SLUG/TESTS.md"
  ( cd "$P" && git add -A && git commit -qm init )
  ( cd "$P" && bash "$RUNNER" --slug "$SLUG" -- sh -c \
      "mkdir -p test-results/x && printf 'v' > test-results/x/video.webm && printf 's' > test-results/x/shot.png" ) >/dev/null 2>&1
  echo "$P"
}

write_settings() { # <proj> <json>
  printf '%s\n' "$2" > "$1/scv/scv_settings.json"
}

run_prh() { # <proj> → OUT/ERR 파일 채움
  local P="$1"
  ( cd "$P" && PATH="$WORK/bin:$PATH" bash "$PRH" "$SLUG" --no-push --no-rerun ) \
    > "$WORK/out" 2> "$WORK/err"
  echo $?
}

echo "── [T1] 기본 on + provider + dry-run → 게시 ──"
P="$(make_proj t1)"
write_settings "$P" '{"NOTIFIER_PROVIDER": "slack", "NOTIFIER_DRY_RUN": "1"}'
printf '{"SLACK_BOT_TOKEN": "xoxb-fake", "SLACK_CHANNEL_ID": "C0FAKE"}\n' > "$P/scv/scv_settings.secret.json"
rc="$(run_prh "$P")"
grep -q "PR created: https://example.invalid/pull/5" "$WORK/out" && ok "PR 생성" || fail "PR 생성 실패: $(cat "$WORK/out")"
[[ "$rc" == "0" ]] && ok "exit 0" || fail "exit $rc"
grep -c "pr-notify: upload" "$WORK/err" | grep -qx 2 && ok "증적 2건 업로드 시도" || fail "업로드 로그: $(grep -c 'pr-notify: upload' "$WORK/err")건"
grep -q "pr-notify: done (2 file(s))" "$WORK/err" && ok "완료 요약" || fail "완료 요약 없음: $(grep 'pr-notify' "$WORK/err" | tail -3)"
grep -q "DRY_RUN" "$WORK/err" && grep -q "example.invalid/pull/5" "$WORK/err" && ok "DRY_RUN 페이로드에 PR URL" || fail "페이로드에 URL 없음"

echo "── [T2] off 만 끈다 ──"
P="$(make_proj t2)"
write_settings "$P" '{"NOTIFIER_PROVIDER": "slack", "NOTIFIER_DRY_RUN": "1", "SCV_PR_NOTIFY": "off"}'
printf '{"SLACK_BOT_TOKEN": "xoxb-fake", "SLACK_CHANNEL_ID": "C0FAKE"}\n' > "$P/scv/scv_settings.secret.json"
rc="$(run_prh "$P")"
grep -q "pr-notify:" "$WORK/err" && fail "off 인데 알림 로그가 있다" || ok "off → 알림 없음"
grep -q "PR created:" "$WORK/out" && ok "PR 은 정상 생성" || fail "PR 생성 안 됨"

echo "── [T3] provider 미설정 → 조용히 건너뜀 ──"
P="$(make_proj t3)"
rc="$(run_prh "$P")"
grep -q "pr-notify:" "$WORK/err" && fail "provider 없는데 알림 로그" || ok "무동작"
[[ "$rc" == "0" ]] && grep -q "PR created:" "$WORK/out" && ok "PR 정상 + exit 0" || fail "rc=$rc"

echo "── [T4] 검증 실패 → 경고 한 줄, PR 무사 ──"
P="$(make_proj t4)"
write_settings "$P" '{"NOTIFIER_PROVIDER": "slack"}'
rc="$(run_prh "$P")"
grep -q "pr-notify:.*continuing" "$WORK/err" && ok "경고 후 계속" || fail "경고 없음: $(grep 'pr-notify' "$WORK/err" | head -2)"
[[ "$rc" == "0" ]] && grep -q "PR created:" "$WORK/out" && ok "PR 정상 + exit 0" || fail "rc=$rc"

echo "── [T5] 키 등록 ──"
# shellcheck source=/dev/null
source "$CORE/scripts/lib/settings.sh"
grep -q "SCV_PR_NOTIFY" <<<"$SCV_PLAIN_KEYS" && ok "공개 키 목록" || fail "SCV_PLAIN_KEYS 에 없음"
grep -q "SCV_PR_NOTIFY" <<<"$SCV_SECRET_KEYS" && fail "비밀 목록에 들어감" || ok "비밀 목록엔 없음"
grep -q '"SCV_PR_NOTIFY": "on"' "$EXAMPLE" && ok "예시 기본값 on" || fail "예시 기본값 없음"
python3 - "$EXAMPLE" <<'PY' && ok "_doc 설명 있음" || fail "_doc 설명 없음"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["_doc"]["SCV_PR_NOTIFY"].strip()
PY

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
