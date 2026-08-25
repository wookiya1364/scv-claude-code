#!/usr/bin/env bash
# test-run-manifest.sh — 첨부는 실행 기록을 따른다 (attachments-run-manifest).
#
# 이름 매칭은 결과 폴더명이 잘리면 깨진다 (Playwright 는 폴더명을 자른다 —
# ai_tm_center 실측: 슬러그 …-readiness-inspection-refine 이 …-readi-<해시> 로
# 저장돼 첨부 0건). 테스트를 돌린 그 실행이 만든 파일 목록을 기록해 두고,
# 첨부는 기록 → 이름 매칭 → 알림 순서로 동작해야 한다.
#
# Covers TESTS.md T1–T5 of 20260825-wookiya1364-attachments-run-manifest.
#
# Run: bash core/tests/test-run-manifest.sh
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
LIB="$CORE/scripts/lib/run-manifest.sh"
RUNNER="$CORE/scripts/run-plan-tests.sh"
COLLECT="$CORE/scripts/collect-artifacts.sh"
PRH="$CORE/scripts/pr-helper.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$LIB" ]]    || { echo "✖ lib 가 없다: $LIB"; exit 1; }
[[ -f "$RUNNER" ]] || { echo "✖ 실행 래퍼가 없다: $RUNNER"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# shellcheck source=/dev/null
source "$LIB"

# 재현 조건: 잘린 폴더 이름. 슬러그 전체는 어떤 경로에도 없다.
SLUG="20260825-tester-readiness-inspection-refine"
CUT="20260825-tester-readi"   # Playwright 가 자른 접두사

echo "── [T1] lib — 기록 왕복 ──"
P1="$WORK/t1"; mkdir -p "$P1/test-results/other-slug-login-chromium"
printf 'old' > "$P1/test-results/other-slug-login-chromium/video.webm"
( cd "$P1"
  marker="$(mktemp)"
  sleep 1
  mkdir -p "test-results/$CUT-07a27-flow-chromium"
  printf 'x' > "test-results/$CUT-07a27-flow-chromium/video.webm"
  printf 'x' > "test-results/$CUT-08967-drawer-chromium.png"
  run_manifest_record "$SLUG" "$marker"
  rm -f "$marker"
) || fail "record 실행 실패"
MF="$P1/$(cd "$P1" && run_manifest_path "$SLUG")"
[[ -f "$MF" ]] && ok "기록 파일이 생겼다" || fail "기록 파일 없음: $MF"
OUT="$(cd "$P1" && run_manifest_read "$SLUG" | LC_ALL=C sort)"
[[ "$OUT" == $'test-results/'"$CUT"$'-07a27-flow-chromium/video.webm\ntest-results/'"$CUT"$'-08967-drawer-chromium.png' ]] \
  && ok "이번 실행이 만든 파일 2개만 기록됐다 (기존 파일·자기 자신 제외)" \
  || fail "기록 내용이 다르다: $OUT"
rm -f "$P1/test-results/$CUT-08967-drawer-chromium.png"
OUT="$(cd "$P1" && run_manifest_read "$SLUG")"
[[ "$OUT" == "test-results/$CUT-07a27-flow-chromium/video.webm" ]] \
  && ok "read 는 지금 존재하는 파일만 준다" || fail "지워진 파일이 나온다: $OUT"
OUT="$(cd "$P1" && run_manifest_read "no-such-slug")"
[[ -z "$OUT" ]] && ok "기록이 없으면 출력 없음 (폴백 신호)" || fail "없는 기록이 출력됨: $OUT"

echo "── [T2] 실행 래퍼 — 실행·종료코드·기록·요약 ──"
P2="$WORK/t2"; mkdir -p "$P2"
cat > "$P2/TESTS.md" <<TESTS
# Test Plan

## How to run

\`\`\`bash
mkdir -p test-results/$CUT-3c1e4-summary-chromium && printf 'x' > test-results/$CUT-3c1e4-summary-chromium/video.webm
\`\`\`

## Pass criteria

- exit 0
TESTS
( cd "$P2" && bash "$RUNNER" --slug "$SLUG" --tests TESTS.md ) 2>"$P2/err"
rc=$?
[[ $rc -eq 0 && -f "$P2/test-results/$CUT-3c1e4-summary-chromium/video.webm" ]] \
  && ok "--tests 가 How-to-run 을 실행한다" || fail "실행 안 됨 (rc=$rc)"
grep -q "manifest: 1 file(s) for $SLUG" "$P2/err" && ok "요약 한 줄 (stderr)" || fail "요약 없음: $(cat "$P2/err")"
OUT="$(cd "$P2" && run_manifest_read "$SLUG")"
[[ "$OUT" == "test-results/$CUT-3c1e4-summary-chromium/video.webm" ]] && ok "래퍼가 기록을 남긴다" || fail "기록이 다르다: $OUT"
( cd "$P2" && bash "$RUNNER" --slug "$SLUG" -- sh -c "printf 'y' > test-results/$CUT-79719-probe-chromium.png" ) 2>/dev/null
OUT="$(cd "$P2" && run_manifest_read "$SLUG")"
[[ "$OUT" == "test-results/$CUT-79719-probe-chromium.png" ]] && ok "-- <cmd> 직접 지정도 기록한다 (기록은 최신 실행으로 교체)" || fail "직접 명령 기록 실패: $OUT"
( cd "$P2" && bash "$RUNNER" --slug "$SLUG" -- sh -c "printf 'z' > test-results/$CUT-bb6b4-fail-chromium.png; exit 7" ) 2>/dev/null
rc=$?
OUT="$(cd "$P2" && run_manifest_read "$SLUG")"
[[ $rc -eq 7 ]] && ok "실패 종료코드가 그대로 전달된다" || fail "종료코드 소실 (rc=$rc)"
[[ "$OUT" == "test-results/$CUT-bb6b4-fail-chromium.png" ]] && ok "실패해도 기록한다 — 실패 증적도 증적" || fail "실패 시 기록 없음: $OUT"

echo "── [T3] collect-artifacts — 기록 1순위·이름 폴백·0건 알림 ──"
P3="$WORK/t3"; mkdir -p "$P3/scv/promote/$SLUG" "$P3/test-results"
: > "$P3/scv/promote/$SLUG/PLAN.md"
# (a) 기록 1순위 — 다른 슬러그의 '더 최신' 파일이 있어도 기록된 것만
( cd "$P3" && bash "$RUNNER" --slug "$SLUG" -- sh -c "mkdir -p test-results/$CUT-e3370-gpu-chromium && printf 'x' > test-results/$CUT-e3370-gpu-chromium/video.webm && printf 'x' > test-results/$CUT-e3370-gpu-chromium/shot.png" ) 2>/dev/null
sleep 1; mkdir -p "$P3/test-results/other-newer-chromium"; printf 'n' > "$P3/test-results/other-newer-chromium/video.webm"; printf 'n' > "$P3/test-results/other-newer-chromium/shot.png"
OUT="$(cd "$P3" && bash "$COLLECT" passed 2>/dev/null)"
grep -q "$CUT-e3370-gpu-chromium/video.webm" <<<"$OUT" && grep -q "$CUT-e3370-gpu-chromium/shot.png" <<<"$OUT" && ! grep -q "other-newer" <<<"$OUT" \
  && ok "기록이 있으면 기록된 파일만 (더 최신인 남의 파일이 있어도)" || fail "기록 우선 실패: $OUT"
# (b) 기록 없음 + 이름 일치 → 기존 이름 매칭
P3b="$WORK/t3b"; mkdir -p "$P3b/scv/promote/$SLUG" "$P3b/test-results/$SLUG-flow-chromium"
: > "$P3b/scv/promote/$SLUG/PLAN.md"; printf 'x' > "$P3b/test-results/$SLUG-flow-chromium/shot.png"
OUT="$(cd "$P3b" && bash "$COLLECT" passed 2>/dev/null)"
grep -q "$SLUG-flow-chromium/shot.png" <<<"$OUT" && ok "기록이 없으면 이름 매칭 폴백" || fail "이름 폴백 실패: $OUT"
# (c) 기록 없음 + 이름 불일치 → 출력 없음 + stderr 알림
P3c="$WORK/t3c"; mkdir -p "$P3c/scv/promote/$SLUG" "$P3c/test-results/$CUT-f50aa-tab-chromium"
: > "$P3c/scv/promote/$SLUG/PLAN.md"; printf 'x' > "$P3c/test-results/$CUT-f50aa-tab-chromium/shot.png"
OUT="$(cd "$P3c" && bash "$COLLECT" passed 2>/dev/null)"
ERR="$(cd "$P3c" && bash "$COLLECT" passed 2>&1 >/dev/null)"
[[ -z "$OUT" ]] && grep -q "belongs to" <<<"$ERR" && ok "0건이면 침묵하지 않는다 — stderr 한 줄" || fail "0건 알림 없음: out=[$OUT] err=[$ERR]"

echo "── [T4] pr-helper dry-run — 기록 경유 첨부 ──"
P4="$WORK/t4"; A="$SLUG"
mkdir -p "$P4/scv/archive/$A"
( cd "$P4" && git init -q && git config user.name t && git config user.email t@x && git checkout -q -b feat/a )
cat > "$P4/scv/archive/$A/PLAN.md" <<PLAN
---
title: readiness inspection refine
slug: $A
author: tester
created_at: 2026-08-25
status: done
kind: feature
lang: english
---

# readiness

## Summary

r.
PLAN
cat > "$P4/scv/archive/$A/TESTS.md" <<TESTS
# Test Plan

## How to run

\`\`\`bash
mkdir -p test-results/$CUT-6909a-flow-chromium && printf 'x' > test-results/$CUT-6909a-flow-chromium/video.webm
\`\`\`

## Pass criteria

- exit 0
TESTS
( cd "$P4" && git add -A && git commit -qm init )
OUT="$(cd "$P4" && bash "$PRH" "$A" --dry-run 2>/dev/null)"
grep -q "^ATTACHMENTS_FILES: 0" <<<"$OUT" && ok "잘린 이름 + 기록 없음 → 0건 (재현)" || fail "재현 조건이 이미 잡힘: $OUT"
( cd "$P4" && bash "$RUNNER" --slug "$A" --tests "scv/archive/$A/TESTS.md" ) 2>/dev/null
OUT="$(cd "$P4" && bash "$PRH" "$A" --dry-run 2>/dev/null)"
grep -q "^ATTACHMENTS_FILES: 1" <<<"$OUT" && grep -q "$CUT-6909a-flow-chromium/video.webm" <<<"$OUT" \
  && ok "래퍼로 돌린 뒤에는 잘린 이름도 붙는다 (0 → 1)" || fail "기록 경유 첨부 실패: $OUT"

echo "── [T5] pr-helper — 열린 PR 이 있으면 갱신, 없으면 생성 ──"
P5="$WORK/t5"; mkdir -p "$P5/bin"
GH_LOG="$P5/gh.log"; GH_LIST="$P5/gh.list"
cat > "$P5/bin/gh" <<FAKE
#!/usr/bin/env bash
echo "\$*" >> "$GH_LOG"
case "\$1 \${2:-}" in
  "pr list")   [[ -s "$GH_LIST" ]] && cat "$GH_LIST" ;;
  "pr create") echo "https://example.invalid/pull/9" ;;
  *)           exit 0 ;;
esac
FAKE
chmod +x "$P5/bin/gh"
mkdir -p "$P5/prj/scv/archive/$A"
cp "$P4/scv/archive/$A/PLAN.md" "$P4/scv/archive/$A/TESTS.md" "$P5/prj/scv/archive/$A/"
( cd "$P5/prj" && git init -q && git config user.name t && git config user.email t@x \
  && git checkout -q -b feat/a && git remote add origin https://github.com/example/repo.git \
  && git add -A && git commit -qm init )
printf '7 https://example.invalid/pull/7\n' > "$GH_LIST"
OUT="$(cd "$P5/prj" && PATH="$P5/bin:$PATH" bash "$PRH" "$A" --no-push --no-rerun 2>/dev/null)"
grep -q "PR updated: https://example.invalid/pull/7" <<<"$OUT" && ok "열린 PR 재사용 — PR updated" || fail "갱신 경로 실패: $OUT"
grep -q "^pr create" "$GH_LOG" && fail "열린 PR 이 있는데 create 를 불렀다" || ok "create 미호출"
: > "$GH_LOG"; : > "$GH_LIST"
OUT="$(cd "$P5/prj" && PATH="$P5/bin:$PATH" bash "$PRH" "$A" --no-push --no-rerun 2>/dev/null)"
grep -q "PR created: https://example.invalid/pull/9" <<<"$OUT" && ok "열린 PR 이 없으면 기존대로 생성" || fail "생성 경로 회귀: $OUT"

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
