#!/usr/bin/env bash
# Render a provider-agnostic report (title + body markdown).
# Inputs via env:
#   PHASE          e.g. "Phase 2 — voice core"
#   STATUS         passed | failed | info
#   PROJECT        project name (derived from PROJECT_NAME env or $(basename $PWD))
#   GIT_SHORT      short commit sha (or "n/a")
#   ATTEMPT        attempt number (integer, default 1)
#   SUMMARY        user-provided summary text
#   DURATION       optional (human-readable, e.g. "2m 14s")
#   TIMESTAMP      ISO 8601
#   SCV_LANG       (v0.4+) language for status labels and body chrome.
#                  Recognized: english | korean | japanese. Anything else → english.
#                  Source order at caller (report.sh): settings.json language →
#                  .env SCV_LANG → English.
# Output: single JSON object `{ "title": "...", "body": "..." }` to stdout.
set -euo pipefail

: "${PHASE:?PHASE required}"
: "${STATUS:?STATUS required}"
: "${PROJECT:?PROJECT required}"
: "${GIT_SHORT:=n/a}"
: "${ATTEMPT:=1}"
: "${SUMMARY:=}"
: "${DURATION:=n/a}"
: "${TIMESTAMP:=$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
: "${SCV_LANG:=english}"

# Per-language label set. Anything outside the recognized values falls back to English.
case "$(printf '%s' "$SCV_LANG" | tr '[:upper:]' '[:lower:]')" in
  korean)
    label_passed="완료"
    label_failed="실패"
    label_in_progress="진행 중"
    meta_project="프로젝트"
    meta_commit="커밋"
    meta_attempt="시도"
    meta_duration="소요"
    cause_label="원인"
    retry_msg="→ 재시도 진행 중"
    no_summary="(요약 없음)"
    progress_default="(진행 보고)"
    ;;
  japanese)
    label_passed="完了"
    label_failed="失敗"
    label_in_progress="進行中"
    meta_project="プロジェクト"
    meta_commit="コミット"
    meta_attempt="試行"
    meta_duration="経過"
    cause_label="原因"
    retry_msg="→ リトライ実行中"
    no_summary="(要約なし)"
    progress_default="(進行報告)"
    ;;
  *)
    # English (default; also fallback for any other language string).
    label_passed="Passed"
    label_failed="Failed"
    label_in_progress="In progress"
    meta_project="Project"
    meta_commit="Commit"
    meta_attempt="Attempt"
    meta_duration="Duration"
    cause_label="Cause"
    retry_msg="→ Retry in progress"
    no_summary="(no summary provided)"
    progress_default="(progress report)"
    ;;
esac

case "$STATUS" in
  passed)
    emoji="✅"; label="$label_passed"
    ;;
  failed)
    emoji="❌"; label="$label_failed"
    ;;
  info)
    emoji="ℹ️"; label="$label_in_progress"
    ;;
  *)
    emoji="•"; label="$STATUS"
    ;;
esac

title="${emoji} ${PHASE} — ${label}"

meta="${meta_project}: *${PROJECT}* | ${meta_commit}: \`${GIT_SHORT}\` | ${meta_attempt}: ${ATTEMPT} | ${meta_duration}: ${DURATION}"

if [[ "$STATUS" == "failed" ]]; then
  body="${meta}

*${cause_label}*
${SUMMARY:-$no_summary}

${retry_msg}"
elif [[ "$STATUS" == "passed" ]]; then
  body="${meta}

${SUMMARY:-$no_summary}"
else
  body="${meta}

${SUMMARY:-$progress_default}"
fi

jq -n --arg t "$title" --arg b "$body" '{title:$t, body:$b}'
