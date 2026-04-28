#!/usr/bin/env bash
# Render a provider-agnostic report (title + body markdown).
# Inputs via env:
#   PHASE          e.g. "Phase 2 — 음성 코어"
#   STATUS         passed | failed | info
#   PROJECT        project name (derived from PROJECT_NAME env or $(basename $PWD))
#   GIT_SHORT      short commit sha (or "n/a")
#   ATTEMPT        attempt number (integer, default 1)
#   SUMMARY        user-provided summary text
#   DURATION       optional (human-readable, e.g. "2m 14s")
#   TIMESTAMP      ISO 8601
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

case "$STATUS" in
  passed)
    emoji="✅"; label="완료"
    ;;
  failed)
    emoji="❌"; label="실패"
    ;;
  info)
    emoji="ℹ️"; label="진행 중"
    ;;
  *)
    emoji="•"; label="$STATUS"
    ;;
esac

title="${emoji} ${PHASE} — ${label}"

meta="프로젝트: *${PROJECT}* | 커밋: \`${GIT_SHORT}\` | 시도: ${ATTEMPT}차 | 소요: ${DURATION}"

if [[ "$STATUS" == "failed" ]]; then
  body="${meta}

*원인*
${SUMMARY:-(no summary provided)}

→ 재시도 진행 중"
elif [[ "$STATUS" == "passed" ]]; then
  body="${meta}

${SUMMARY:-(no summary provided)}"
else
  body="${meta}

${SUMMARY:-(진행 보고)}"
fi

jq -n --arg t "$title" --arg b "$body" '{title:$t, body:$b}'
