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
    emoji="✅"; label="Passed"
    ;;
  failed)
    emoji="❌"; label="Failed"
    ;;
  info)
    emoji="ℹ️"; label="In progress"
    ;;
  *)
    emoji="•"; label="$STATUS"
    ;;
esac

title="${emoji} ${PHASE} — ${label}"

meta="Project: *${PROJECT}* | Commit: \`${GIT_SHORT}\` | Attempt: ${ATTEMPT} | Duration: ${DURATION}"

if [[ "$STATUS" == "failed" ]]; then
  body="${meta}

*Cause*
${SUMMARY:-(no summary provided)}

→ Retry in progress"
elif [[ "$STATUS" == "passed" ]]; then
  body="${meta}

${SUMMARY:-(no summary provided)}"
else
  body="${meta}

${SUMMARY:-(progress report)}"
fi

jq -n --arg t "$title" --arg b "$body" '{title:$t, body:$b}'
