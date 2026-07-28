#!/usr/bin/env bash
# Slack adapter — implements the notifier contract via Slack Web API.
# Requires: jq, curl
# Env:
#   SLACK_BOT_TOKEN                     (xoxb-...)
#   SLACK_CHANNEL_ID                    (default channel)
#   SLACK_CHANNEL_ID_<EVENT_UPPER>      (per-event override)

notifier_validate_env() {
  require_cmd jq || return 1
  require_cmd curl || return 1
  env_require SLACK_BOT_TOKEN || return 1
}

notifier_resolve_channel() {
  local event="$1"
  local suffix; suffix=$(event_to_env_suffix "$event")
  local var="SLACK_CHANNEL_ID_${suffix}"
  local val="${!var:-}"
  if [[ -n "$val" ]]; then
    echo "$val"
    return 0
  fi
  if [[ -n "${SLACK_CHANNEL_ID:-}" ]]; then
    echo "$SLACK_CHANNEL_ID"
    return 0
  fi
  echo "✖ No Slack channel configured (looked up $var and SLACK_CHANNEL_ID)" >&2
  return 1
}

notifier_post_message() {
  local channel="$1" title="$2" body="$3"
  local payload
  payload=$(jq -n \
    --arg c "$channel" \
    --arg t "$title" \
    --arg b "$body" \
    '{
      channel: $c,
      text: $t,
      blocks: [
        { type: "header", text: { type: "plain_text", text: $t, emoji: true } },
        { type: "section", text: { type: "mrkdwn", text: $b } }
      ]
    }')

  if is_dry_run; then
    dry_run_stderr "slack:chat.postMessage" "channel=$channel" "$payload"
    echo "DRY-RUN-TS-$(date +%s)"
    return 0
  fi

  local resp
  resp=$(curl -sS -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data-binary "$payload")

  if ! echo "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo "✖ Slack chat.postMessage failed: $(echo "$resp" | jq -r '.error // .')" >&2
    return 1
  fi
  echo "$resp" | jq -r '.ts'
}

# Slack 2-step external file upload with optional threading.
# https://api.slack.com/methods/files.getUploadURLExternal
# https://api.slack.com/methods/files.completeUploadExternal
notifier_upload_file() {
  local channel="$1" file="$2" thread_ref="${3:-}"
  local title="${4:-$(basename "$file")}"
  local size filename
  if [[ ! -f "$file" ]]; then
    echo "✖ Slack upload: file not found: $file" >&2
    return 1
  fi
  size=$(wc -c <"$file" | tr -d ' ')
  filename=$(basename "$file")

  if is_dry_run; then
    dry_run_stderr "slack:files.getUploadURLExternal + completeUploadExternal" \
      "channel=$channel" "thread_ts=$thread_ref" "file=$file" "size=$size"
    return 0
  fi

  # Step 1: request upload URL + file_id
  local step1
  step1=$(curl -sS -X POST "https://slack.com/api/files.getUploadURLExternal" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=utf-8" \
    --data-urlencode "filename=$filename" \
    --data-urlencode "length=$size")
  if ! echo "$step1" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo "✖ Slack files.getUploadURLExternal: $(echo "$step1" | jq -r '.error // .')" >&2
    return 1
  fi
  local url file_id
  url=$(echo "$step1" | jq -r '.upload_url')
  file_id=$(echo "$step1" | jq -r '.file_id')

  # Step 2: upload bytes
  if ! curl -sS -X POST "$url" --data-binary "@$file" >/dev/null; then
    echo "✖ Slack file upload (PUT bytes) failed" >&2
    return 1
  fi

  # Step 3: complete upload (attach to channel with optional thread_ts)
  local complete_payload
  if [[ -n "$thread_ref" && "$thread_ref" != DRY-* ]]; then
    complete_payload=$(jq -n \
      --arg c "$channel" --arg fid "$file_id" --arg title "$title" --arg ts "$thread_ref" \
      '{files:[{id:$fid, title:$title}], channel_id:$c, thread_ts:$ts}')
  else
    complete_payload=$(jq -n \
      --arg c "$channel" --arg fid "$file_id" --arg title "$title" \
      '{files:[{id:$fid, title:$title}], channel_id:$c}')
  fi

  local resp
  resp=$(curl -sS -X POST "https://slack.com/api/files.completeUploadExternal" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data-binary "$complete_payload")
  if ! echo "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo "✖ Slack files.completeUploadExternal: $(echo "$resp" | jq -r '.error // .')" >&2
    return 1
  fi
  return 0
}
