#!/usr/bin/env bash
# test-evidence-pacing.sh — 증적 영상은 사람 속도로 (evidence-pacing).
#
# 사람은 화면 전환당 ~2초가 있어야 인지한다. 스펙이 기계 속도로 달려 영상이
# 임계(기본 4초)보다 짧으면 경고한다 — 경고만, 막지 않는다. ffprobe 가 없으면
# 조용히 건너뛴다.
#
# Covers TESTS.md T1–T5 of 20260825-wookiya1364-evidence-pacing.
#
# Run: bash core/tests/test-evidence-pacing.sh
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
LIB="$CORE/scripts/lib/evidence.sh"
PRH="$CORE/scripts/pr-helper.sh"
RUNNER="$CORE/scripts/run-plan-tests.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$LIB" ]] || { echo "✖ lib 가 없다: $LIB"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# shellcheck source=/dev/null
source "$LIB"

echo "── [T1] 임계 판독 ──"
[[ "$(evidence_min_seconds)" == "4" ]] && ok "기본 4" || fail "기본이 4 가 아님: $(evidence_min_seconds)"
[[ "$(SCV_EVIDENCE_MIN_SECONDS=7 evidence_min_seconds)" == "7" ]] && ok "설정 7 → 7" || fail "설정값 무시"
for bad in abc 0 -3; do
  [[ "$(SCV_EVIDENCE_MIN_SECONDS=$bad evidence_min_seconds)" == "4" ]] && ok "이상값 [$bad] → 4" || fail "이상값 [$bad] 폴백 실패"
done

HAVE_FF=0
command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 && HAVE_FF=1
if [[ $HAVE_FF -eq 1 ]]; then
  V="$WORK/short.webm"
  ffmpeg -nostdin -y -loglevel error -f lavfi -i color=c=black:s=64x64:d=1 -t 1 "$V" 2>/dev/null || HAVE_FF=0
fi

echo "── [T2] 길이 측정 + 경고 ──"
if [[ $HAVE_FF -eq 1 ]]; then
  ERR="$(evidence_warn_short "$V" 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] && grep -q "evidence:" <<<"$ERR" && grep -q "shorter than" <<<"$ERR" \
    && ok "1초 영상 + 임계 4 → 경고" || fail "경고 없음 (rc=$rc): $ERR"
  ERR="$(SCV_EVIDENCE_MIN_SECONDS=1 evidence_warn_short "$V" 2>&1)"
  [[ -z "$ERR" ]] && ok "임계 1 → 침묵" || fail "임계 1 인데 경고: $ERR"
  ERR="$(evidence_warn_short "$WORK/no-such.webm" 2>&1)"; rc=$?
  [[ $rc -eq 0 && -z "$ERR" ]] && ok "없는 파일 → 무경고·exit 0" || fail "없는 파일 처리 (rc=$rc): $ERR"
else
  ok "skip — ffmpeg/ffprobe 없음 (T2)"
fi

echo "── [T3] pr-helper 연결 ──"
if [[ $HAVE_FF -eq 1 ]]; then
  SLUG="20260825-tester-pacing-feature"
  P="$WORK/prj"; mkdir -p "$P/scv/archive/$SLUG"
  ( cd "$P" && git init -q && git config user.name t && git config user.email t@x \
    && git checkout -q -b feat/p && git remote add origin https://github.com/example/repo.git )
  printf -- '---\ntitle: p\nslug: %s\nauthor: t\ncreated_at: 2026-08-25\nstatus: done\nkind: feature\nlang: english\n---\n\n# p\n\n## Summary\n\np.\n' "$SLUG" > "$P/scv/archive/$SLUG/PLAN.md"
  printf '# T\n\n## How to run\n\n```bash\ntrue\n```\n\n## Pass criteria\n\n- ok\n' > "$P/scv/archive/$SLUG/TESTS.md"
  ( cd "$P" && git add -A && git commit -qm init )
  mkdir -p "$P/test-results/x"; cp "$V" "$P/test-results/x/video.webm"
  ( cd "$P" && bash "$RUNNER" --slug "$SLUG" -- sh -c "touch test-results/x/video.webm" ) >/dev/null 2>&1
  ERR="$( cd "$P" && bash "$PRH" "$SLUG" --dry-run 2>&1 >/dev/null )"
  grep -q "evidence:" <<<"$ERR" && ok "pr-helper 가 짧은 영상을 경고" || fail "pr-helper 경고 없음: $ERR"
else
  ok "skip — ffmpeg/ffprobe 없음 (T3)"
fi

echo "── [T4] ffprobe 부재 → 침묵 ──"
FAKE="$WORK/fakebin"; mkdir -p "$FAKE"
for c in bash grep tr basename dirname printf; do p="$(command -v "$c")" && ln -s "$p" "$FAKE/$c" 2>/dev/null; done
ERR="$(PATH="$FAKE" bash -c "source '$LIB'; evidence_warn_short '$WORK/short.webm'" 2>&1)"; rc=$?
[[ $rc -eq 0 && -z "$ERR" ]] && ok "ffprobe 없음 → 무경고·exit 0" || fail "부재 처리 (rc=$rc): $ERR"

echo "── [T5] 키 등록 ──"
# shellcheck source=/dev/null
source "$CORE/scripts/lib/settings.sh"
grep -q "SCV_EVIDENCE_MIN_SECONDS" <<<"$SCV_PLAIN_KEYS" && ok "공개 키 목록" || fail "SCV_PLAIN_KEYS 에 없음"
grep -q "SCV_EVIDENCE_MIN_SECONDS" <<<"$SCV_SECRET_KEYS" && fail "비밀 목록" || ok "비밀 목록엔 없음"
grep -q '"SCV_EVIDENCE_MIN_SECONDS": "4"' "$EXAMPLE" && ok "예시 기본값 4" || fail "예시 기본값 없음"
python3 - "$EXAMPLE" <<'PY' && ok "_doc 설명 있음" || fail "_doc 설명 없음"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["_doc"]["SCV_EVIDENCE_MIN_SECONDS"].strip()
PY

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
