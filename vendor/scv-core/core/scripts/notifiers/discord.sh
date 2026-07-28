#!/usr/bin/env bash
# Discord adapter — implements the notifier contract via Discord v10 Bot API.
# Requires: jq, curl
# Env:
#   DISCORD_BOT_TOKEN
#   DISCORD_CHANNEL_ID                     (default channel)
#   DISCORD_CHANNEL_ID_<EVENT_UPPER>       (per-event override)

notifier_validate_env() {
  require_cmd jq || return 1
  require_cmd curl || return 1
  env_require DISCORD_BOT_TOKEN || return 1
}

notifier_resolve_channel() {
  local event="$1"
  local suffix; suffix=$(event_to_env_suffix "$event")
  local var="DISCORD_CHANNEL_ID_${suffix}"
  local val="${!var:-}"
  if [[ -n "$val" ]]; then
    echo "$val"
    return 0
  fi
  if [[ -n "${DISCORD_CHANNEL_ID:-}" ]]; then
    echo "$DISCORD_CHANNEL_ID"
    return 0
  fi
  echo "✖ No Discord channel configured (looked up $var and DISCORD_CHANNEL_ID)" >&2
  return 1
}

# Discord embed color per status (hex → decimal)
# passed = green, failed = red, info = blue, default gray
_discord_color() {
  case "${1:-}" in
    passed)  echo 3066993 ;;   # #2ecc71
    failed)  echo 15158332 ;;  # #e74c3c
    info)    echo 3447003 ;;   # #3498db
    *)       echo 9807270 ;;   # #95a5a6
  esac
}

notifier_post_message() {
  local channel="$1" title="$2" body="$3"
  local color; color=$(_discord_color "${DISCORD_STATUS_HINT:-}")

  local payload
  payload=$(jq -n \
    --arg t "$title" \
    --arg b "$body" \
    --argjson c "$color" \
    '{
      embeds: [
        {
          title: $t,
          description: $b,
          color: $c
        }
      ]
    }')

  if is_dry_run; then
    dry_run_stderr "discord:messages" "channel=$channel" "$payload"
    echo "DRY-RUN-MID-$(date +%s)"
    return 0
  fi

  local resp
  resp=$(curl -sS -X POST "https://discord.com/api/v10/channels/${channel}/messages" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "$payload")

  if ! echo "$resp" | jq -e '.id' >/dev/null 2>&1; then
    echo "✖ Discord messages failed: $resp" >&2
    return 1
  fi
  echo "$resp" | jq -r '.id'
}

# Discord single-step multipart file upload with message_reference threading.
# https://discord.com/developers/docs/resources/channel#create-message
notifier_upload_file() {
  local channel="$1" file="$2" thread_ref="${3:-}"
  local filename
  if [[ ! -f "$file" ]]; then
    echo "✖ Discord upload: file not found: $file" >&2
    return 1
  fi
  filename=$(basename "$file")

  if is_dry_run; then
    dry_run_stderr "discord:channels/.../messages (multipart)" \
      "channel=$channel" "message_reference=$thread_ref" "file=$file"
    return 0
  fi

  local payload_json
  if [[ -n "$thread_ref" && "$thread_ref" != DRY-* ]]; then
    payload_json=$(jq -n --arg fn "$filename" --arg ref "$thread_ref" --arg ch "$channel" '{
      attachments: [{ id: 0, filename: $fn }],
      message_reference: { message_id: $ref, channel_id: $ch, fail_if_not_exists: false }
    }')
  else
    payload_json=$(jq -n --arg fn "$filename" '{
      attachments: [{ id: 0, filename: $fn }]
    }')
  fi

  local resp
  resp=$(curl -sS -X POST "https://discord.com/api/v10/channels/${channel}/messages" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -F "payload_json=$payload_json" \
    -F "files[0]=@$file")

  if ! echo "$resp" | jq -e '.id' >/dev/null 2>&1; then
    echo "✖ Discord attachment upload: $resp" >&2
    return 1
  fi
  return 0
}
