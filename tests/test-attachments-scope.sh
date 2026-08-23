#!/usr/bin/env bash
# test-attachments-scope.sh — attachments follow the plan, not the folder (v0.32.0+).
#
# Covers TESTS.md T1–T3 of 20260821-wookiya1364-slug-scoped-attachments:
#   T1 lib — mode (env > settings file > default slug; only `all` turns it off), path
#      filter, slug resolution (explicit > env > single active promote plan > "")
#   T2 pr-helper --dry-run — slug scope lists only this slug's files; all lists
#      everything; the re-run helper extracts the How-to-run block
#   T3 collect-artifacts — slug scope picks this slug's latest file; falls back
#      to any slug with a notice when no slug can be resolved; all = legacy
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
LIB="$CORE/scripts/lib/attachment-scope.sh"
PRH="$CORE/scripts/pr-helper.sh"
COLLECT="$CORE/scripts/collect-artifacts.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# shellcheck source=/dev/null
source "$LIB"

echo "── [T1] lib — mode ──"
( cd "$WORK" && [[ "$(attachment_scope_mode)" == "slug" ]] ) && ok "default mode is slug" || fail "default mode not slug"
( cd "$WORK" && SCV_ATTACHMENTS_SCOPE=all attachment_scope_mode | grep -qx all ) && ok "env all → all" || fail "env all ignored"
( cd "$WORK" && SCV_ATTACHMENTS_SCOPE=ALL attachment_scope_mode | grep -qx all ) && ok "env ALL (any case) → all" || fail "env ALL ignored"
( cd "$WORK" && SCV_ATTACHMENTS_SCOPE=maybe attachment_scope_mode | grep -qx slug ) && ok "unknown value → slug" || fail "unknown value not slug"
# 설정은 scv/ 아래 파일에서 읽는다 — 프로젝트 루트의 .env 는 더 이상 설정이 아니다.
mkdir -p "$WORK/envproj/scv"
printf '{"SCV_ATTACHMENTS_SCOPE": "all"}\n' > "$WORK/envproj/scv/scv_settings.json"
( cd "$WORK/envproj" && unset SCV_ATTACHMENTS_SCOPE; attachment_scope_mode | grep -qx all ) && ok "settings all → all" || fail "settings file not read"
( cd "$WORK/envproj" && SCV_ATTACHMENTS_SCOPE=slug attachment_scope_mode | grep -qx slug ) && ok "환경변수가 설정 파일을 이긴다" || fail "env did not win over the settings file"
# 옛 파일에 적어두면 무시된다 — 조용히 읽히면 이사한 의미가 없다
mkdir -p "$WORK/oldenv"; printf 'SCV_ATTACHMENTS_SCOPE=all\n' > "$WORK/oldenv/.env"
( cd "$WORK/oldenv" && unset SCV_ATTACHMENTS_SCOPE; attachment_scope_mode 2>/dev/null | grep -qx slug ) && ok ".env 의 값은 읽히지 않는다" || fail ".env still read"

echo "── [T1] lib — filter ──"
OUT="$(printf 'test-results/A-x/video.webm\ntest-results/B-y/video.webm\ntest-results/A-z/shot.png\n' | attachment_scope_filter A)"
[[ "$OUT" == $'test-results/A-x/video.webm\ntest-results/A-z/shot.png' ]] && ok "filter keeps only paths containing the slug" || fail "filter wrong: $OUT"
OUT="$(printf 'test-results/A-x/video.webm\ntest-results/B-y/video.webm\n' | attachment_scope_filter "")"
[[ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 2 ]] && ok "empty slug → passthrough" || fail "empty slug filtered something"

echo "── [T1] lib — slug resolution ──"
[[ "$(attachment_scope_resolve_slug explicit-one)" == "explicit-one" ]] && ok "explicit slug wins" || fail "explicit ignored"
[[ "$(SCV_ATTACHMENTS_SLUG=from-env attachment_scope_resolve_slug)" == "from-env" ]] && ok "SCV_ATTACHMENTS_SLUG used" || fail "env slug ignored"
P1="$WORK/one"; mkdir -p "$P1/scv/promote/20260821-tester-only-plan"; : > "$P1/scv/promote/20260821-tester-only-plan/PLAN.md"
( cd "$P1" && [[ "$(attachment_scope_resolve_slug)" == "20260821-tester-only-plan" ]] ) && ok "single active plan resolves" || fail "single plan not resolved"
P2="$WORK/two"; mkdir -p "$P2/scv/promote/a" "$P2/scv/promote/b"; : > "$P2/scv/promote/a/PLAN.md"; : > "$P2/scv/promote/b/PLAN.md"
( cd "$P2" && [[ -z "$(attachment_scope_resolve_slug)" ]] ) && ok "several plans → empty (caller falls back)" || fail "several plans resolved to something"
P0="$WORK/zero"; mkdir -p "$P0/scv/promote"
( cd "$P0" && [[ -z "$(attachment_scope_resolve_slug)" ]] ) && ok "no plan → empty" || fail "no plan resolved to something"

echo "── [T2] pr-helper --dry-run — scope ──"
PRJ="$WORK/prj"; A="20260821-tester-feature-a"; B="20260820-tester-feature-b"
mkdir -p "$PRJ/scv/archive/$A" "$PRJ/test-results/$B-login-chromium" "$PRJ/test-results/$B-cart-chromium"
( cd "$PRJ" && git init -q && git config user.name t && git config user.email t@x && git checkout -q -b feat/a )
cat > "$PRJ/scv/archive/$A/PLAN.md" <<PLAN
---
title: feature A
slug: $A
author: tester
created_at: 2026-08-21
status: done
kind: feature
lang: english
---

# feature A

## Summary

A.
PLAN
cat > "$PRJ/scv/archive/$A/TESTS.md" <<TESTS
# Test Plan — feature A

## How to run

\`\`\`bash
mkdir -p test-results/$A-flow-chromium && printf 'x' > test-results/$A-flow-chromium/video.webm
\`\`\`

## Pass criteria

- exit 0
TESTS
printf 'x' > "$PRJ/test-results/$B-login-chromium/video.webm"; printf 'x' > "$PRJ/test-results/$B-cart-chromium/shot.png"
( cd "$PRJ" && git add -A && git commit -qm init )
OUT="$(cd "$PRJ" && bash "$PRH" "$A" --dry-run 2>/dev/null)"
grep -q "^ATTACHMENTS_SCOPE: slug" <<<"$OUT" && ok "dry-run reports scope=slug" || fail "scope line missing"
grep -q "^ATTACHMENTS_FILES: 0" <<<"$OUT" && ok "slug scope: other slug's files are not attached" || fail "slug scope leaked other files: $(grep -A3 ATTACHMENTS_FILES <<<"$OUT")"
[[ -d "$PRJ/test-results/$A-flow-chromium" ]] && fail "dry-run re-ran the tests" || ok "dry-run never re-runs the plan's tests"
OUT="$(cd "$PRJ" && SCV_ATTACHMENTS_SCOPE=all bash "$PRH" "$A" --dry-run 2>/dev/null)"
grep -q "^ATTACHMENTS_SCOPE: all" <<<"$OUT" && ok "all mode reported" || fail "all mode not reported"
grep -q "^ATTACHMENTS_FILES: 2" <<<"$OUT" && ok "all mode attaches everything (legacy)" || fail "all mode count wrong"
mkdir -p "$PRJ/test-results/$A-flow-chromium"; printf 'x' > "$PRJ/test-results/$A-flow-chromium/video.webm"
OUT="$(cd "$PRJ" && bash "$PRH" "$A" --dry-run 2>/dev/null)"
grep -q "^ATTACHMENTS_FILES: 1" <<<"$OUT" && grep -q "$A-flow-chromium/video.webm" <<<"$OUT" && ok "slug scope keeps this slug's video only" || fail "slug scope wrong with own video present"
CMD="$(attachment_scope_read_test_command "$PRJ/scv/archive/$A/TESTS.md")"
grep -q "mkdir -p test-results/$A-flow-chromium" <<<"$CMD" && ok "re-run helper extracts the How-to-run block" || fail "How-to-run extraction failed"
rm -rf "$PRJ/test-results/$A-flow-chromium"
( cd "$PRJ" && bash -c "$CMD" ) && [[ -f "$PRJ/test-results/$A-flow-chromium/video.webm" ]] && ok "the extracted block re-creates this slug's evidence" || fail "re-run block did not produce evidence"

echo "── [T3] collect-artifacts — scope ──"
CP="$WORK/cp"; mkdir -p "$CP/scv/promote" "$CP/test-results/$A-flow-chromium" "$CP/test-results/$B-login-chromium"
printf 'x' > "$CP/test-results/$B-login-chromium/video.webm"; sleep 1; printf 'x' > "$CP/test-results/$A-flow-chromium/video.webm"; sleep 1; printf 'x' > "$CP/test-results/$B-login-chromium/shot.png"
OUT="$(cd "$CP" && SCV_ATTACHMENTS_SLUG=$A bash "$COLLECT" passed 2>/dev/null)"
grep -q "$A-flow-chromium/video.webm" <<<"$OUT" && ! grep -q "$B" <<<"$OUT" && ok "--slug scopes the report attachments" || fail "report scope wrong: $OUT"
mkdir -p "$CP/scv/promote/$A"; : > "$CP/scv/promote/$A/PLAN.md"
OUT="$(cd "$CP" && bash "$COLLECT" passed 2>/dev/null)"
grep -q "$A-flow-chromium/video.webm" <<<"$OUT" && ! grep -q "$B" <<<"$OUT" && ok "single active plan scopes the report" || fail "single-plan inference failed: $OUT"
rm -rf "$CP/scv/promote/$A"
ERR="$(cd "$CP" && bash "$COLLECT" passed 2>&1 >/dev/null)"; OUT="$(cd "$CP" && bash "$COLLECT" passed 2>/dev/null)"
grep -q "no slug to scope by" <<<"$ERR" && grep -q "$B-login-chromium/shot.png" <<<"$OUT" && ok "no slug → legacy latest-of-any + notice" || fail "fallback wrong: err=[$ERR] out=[$OUT]"
OUT="$(cd "$CP" && SCV_ATTACHMENTS_SCOPE=all SCV_ATTACHMENTS_SLUG=$A bash "$COLLECT" passed 2>/dev/null)"
grep -q "$B-login-chromium/shot.png" <<<"$OUT" && ok "all mode ignores the slug (legacy)" || fail "all mode still scoped"

echo
echo "── result: PASS=$PASS FAIL=$FAIL ──"
[[ $FAIL -eq 0 ]] || exit 1
