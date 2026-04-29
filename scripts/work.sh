#!/usr/bin/env bash
# work.sh — context emitter for /scv:work + archive move helper.
#
# Usage:
#   work.sh                       List active promote plans (no slug → prompt user)
#   work.sh <slug>                Resolve folder, emit PLAN / TESTS / Related docs
#   work.sh <slug> --archive      Move promote/<slug>/ → archive/<slug>/
#                                 Auto-writes ARCHIVED_AT.md.
#   work.sh <slug> --archive --reason="..."
#
# Output header (same style as promote-helper.sh) — Claude parses these keys:
#   MODE / TODAY / AUTHOR / GRAPHIFY_SKILL / GRAPH_STATUS
#   TARGET_SLUG / TARGET_DIR / PLAN_FILE / TESTS_FILE
#
# Content blocks:
#   === active promote plans ===
#   === related documents (from PLAN.md) ===

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
READPATH="$SCRIPT_DIR/readpath.sh"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"

PROMOTE_DIR="${PROMOTE_DIR:-scv/promote}"
ARCHIVE_DIR="${ARCHIVE_DIR:-scv/archive}"
STATE_FILE="${STATE_FILE:-scv/readpath.json}"

MODE="prepare"
TARGET_SLUG=""
REASON=""

for a in "$@"; do
  case "$a" in
    --archive)    MODE="archive" ;;
    --reason=*)   REASON="${a#--reason=}" ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    -*)  echo "Unknown flag: $a" >&2; exit 1 ;;
    *)
      if [[ -z "$TARGET_SLUG" ]]; then
        TARGET_SLUG="$a"
      else
        echo "Multiple slugs not supported: $a" >&2; exit 1
      fi ;;
  esac
done

# ---------- header ----------
echo "MODE: $MODE"
echo "TODAY: $(date +%Y-%m-%d)"

AUTHOR=""
if command -v git >/dev/null 2>&1; then
  raw_name=$(git config user.name 2>/dev/null || true)
  if [[ -n "$raw_name" ]]; then
    AUTHOR=$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-_')
  fi
fi
[[ -z "$AUTHOR" ]] && AUTHOR="unknown"
echo "AUTHOR: $AUTHOR"

# Graphify skill check (shared logic with promote-helper.sh)
GRAPHIFY_SKILL="missing"
for candidate in \
  "$HOME/.claude/skills/graphify/SKILL.md" \
  "$HOME/.claude/plugins/cache/"*/skills/graphify/SKILL.md; do
  if [[ -f "$candidate" ]]; then
    GRAPHIFY_SKILL="available"
    break
  fi
done
echo "GRAPHIFY_SKILL: $GRAPHIFY_SKILL"

GRAPH_STATUS="n/a"
if [[ "$GRAPHIFY_SKILL" == "available" ]]; then
  GRAPH_DIR=".graphify/docs/graphify-out"
  if [[ ! -d "$GRAPH_DIR" ]]; then
    GRAPH_STATUS="missing"
  elif [[ ! -f "$STATE_FILE" ]]; then
    GRAPH_STATUS="built"
  else
    graph_mt=$(stat -c %Y "$GRAPH_DIR" 2>/dev/null || echo 0)
    state_mt=$(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0)
    if [[ "$graph_mt" -ge "$state_mt" ]]; then
      GRAPH_STATUS="built"
    else
      GRAPH_STATUS="stale"
    fi
  fi
fi
echo "GRAPH_STATUS: $GRAPH_STATUS"

# ---------- helpers ----------

# resolve_target <slug>
# Emits the resolved path on stdout, or on multiple matches emits one per line
# Returns: 0 single match, 1 no match, 2 ambiguous
resolve_target() {
  local slug="$1"
  if [[ -d "$PROMOTE_DIR/$slug" ]]; then
    echo "$PROMOTE_DIR/$slug"
    return 0
  fi
  local hits=()
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    local name
    name=$(basename "$d")
    if [[ "$name" == *"$slug"* ]]; then
      hits+=("$d")
    fi
  done < <(find "$PROMOTE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)

  if [[ ${#hits[@]} -eq 1 ]]; then
    echo "${hits[0]}"
    return 0
  fi
  if [[ ${#hits[@]} -gt 1 ]]; then
    printf '%s\n' "${hits[@]}"
    return 2
  fi
  return 1
}

list_promote_plans() {
  echo "=== active promote plans ==="
  local count=0
  for d in "$PROMOTE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local name title
    name=$(basename "$d")
    if [[ -f "${d}PLAN.md" ]]; then
      title=$(awk '/^title:/{sub(/^title: */, ""); gsub(/"/, ""); print; exit}' "${d}PLAN.md" 2>/dev/null)
      count=$((count+1))
      if [[ -n "$title" ]]; then
        echo "- $name  — $title"
      else
        echo "- $name"
      fi
    fi
  done
  [[ $count -eq 0 ]] && echo "(none)"
}

# ---------- archive mode ----------

if [[ "$MODE" == "archive" ]]; then
  if [[ -z "$TARGET_SLUG" ]]; then
    echo "ERROR: --archive requires <slug>" >&2
    exit 1
  fi
  if resolved=$(resolve_target "$TARGET_SLUG"); then
    :
  else
    rc=$?
    if [[ $rc -eq 2 ]]; then
      echo "ERROR: ambiguous slug '$TARGET_SLUG'; multiple matches:" >&2
      echo "$resolved" >&2
    else
      echo "ERROR: no promote folder matches slug '$TARGET_SLUG'" >&2
    fi
    exit 1
  fi
  TARGET_DIR="$resolved"
  NAME=$(basename "$TARGET_DIR")
  DEST="$ARCHIVE_DIR/$NAME"
  if [[ -e "$DEST" ]]; then
    echo "ERROR: archive destination already exists: $DEST" >&2
    exit 1
  fi
  mkdir -p "$ARCHIVE_DIR"
  mv "$TARGET_DIR" "$DEST"

  ARCHIVED_DATE=$(date +%Y-%m-%d)
  REASON_LINE="${REASON:-tests passed}"
  BODY_REASON=$(printf '%s' "${REASON:-All TESTS scenarios passed}")

  # Extract supersedes from the newly-archived PLAN.md (if any) so the
  # archive record preserves the audit trail of what this plan replaced.
  # regression.sh reads from PLAN.md directly; ARCHIVED_AT.md is for humans.
  SUPERSEDES_BLOCK=""
  PLAN_IN_ARCHIVE="$DEST/PLAN.md"
  if [[ -f "$PLAN_IN_ARCHIVE" ]]; then
    SUPERSEDES_ITEMS=$(yaml_get_list "$PLAN_IN_ARCHIVE" supersedes)
    if [[ -n "$SUPERSEDES_ITEMS" ]]; then
      SUPERSEDES_BLOCK="supersedes:
"
      while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        SUPERSEDES_BLOCK="${SUPERSEDES_BLOCK}  - ${item}
"
      done <<< "$SUPERSEDES_ITEMS"
    fi
  fi

  cat > "$DEST/ARCHIVED_AT.md" <<EOF
---
archived_at: $ARCHIVED_DATE
archived_by: $AUTHOR
reason: $REASON_LINE
${SUPERSEDES_BLOCK}---

# Archive record

This plan was archived on $ARCHIVED_DATE.

## Reason

- $BODY_REASON
EOF

  echo "ARCHIVED: $TARGET_DIR -> $DEST"
  echo "WROTE: $DEST/ARCHIVED_AT.md"
  exit 0
fi

# ---------- prepare mode (default) ----------

echo ""
list_promote_plans

if [[ -z "$TARGET_SLUG" ]]; then
  echo ""
  echo "TARGET_SLUG: (none — pass a slug arg or pick from the list above)"
  exit 0
fi

if resolved=$(resolve_target "$TARGET_SLUG"); then
  :
else
  rc=$?
  if [[ $rc -eq 2 ]]; then
    echo ""
    echo "ERROR: slug '$TARGET_SLUG' matches multiple folders:" >&2
    echo "$resolved" >&2
    exit 2
  fi
  echo ""
  echo "ERROR: no promote folder matches slug '$TARGET_SLUG'" >&2
  exit 1
fi

TARGET_DIR="$resolved"
SLUG_NAME=$(basename "$TARGET_DIR")
PLAN="$TARGET_DIR/PLAN.md"
TESTS="$TARGET_DIR/TESTS.md"

echo ""
echo "TARGET_SLUG: $SLUG_NAME"
echo "TARGET_DIR: $TARGET_DIR"

if [[ -f "$PLAN" ]]; then
  echo "PLAN_FILE: $PLAN"
else
  echo "PLAN_FILE: (MISSING — $PLAN not found; user must create before /scv:work can proceed)"
fi

if [[ -f "$TESTS" ]]; then
  echo "TESTS_FILE: $TESTS"
else
  echo "TESTS_FILE: (MISSING — $TESTS not found)"
fi

# Related Documents
echo ""
echo "=== related documents (from PLAN.md) ==="
if [[ -f "$PLAN" ]]; then
  related=$(awk '
    /^## Related Documents/ { inblock=1; next }
    /^## / && inblock { exit }
    inblock { print }
  ' "$PLAN" | grep -oE '\[[^]]+\]\(\./[^)]+\)' | sed 's|^.*(\./||; s|)$||')
  if [[ -z "$related" ]]; then
    echo "(none — PLAN.md Related Documents section is empty)"
  else
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      if [[ -f "$TARGET_DIR/$rel" ]]; then
        echo "- $TARGET_DIR/$rel"
      else
        echo "- $TARGET_DIR/$rel  (MISSING)"
      fi
    done <<< "$related"
  fi
else
  echo "(PLAN.md missing — cannot enumerate)"
fi

# External refs (refs: frontmatter array — vendor-agnostic: jira/linear/confluence/pr/...)
echo ""
echo "=== external refs (from PLAN.md frontmatter refs:) ==="
if [[ -f "$PLAN" ]]; then
  # Separator is '|' (non-whitespace so bash `read` doesn't collapse empty fields
  # the way it does with tabs when IFS contains only whitespace characters).
  refs_data=$(awk '
    BEGIN { fm=0; in_refs=0; type=""; id=""; url="" }
    function emit() {
      if (type != "" || id != "" || url != "") {
        printf "%s|%s|%s\n", type, id, url
      }
      type=""; id=""; url=""
    }
    /^---[[:space:]]*$/ {
      fm++
      if (fm == 2) { emit(); exit }
      next
    }
    fm != 1 { next }
    /^refs:[[:space:]]*$/ { in_refs=1; next }
    in_refs && /^[^ #]/ { emit(); in_refs=0 }
    in_refs && /^  - type:/ {
      emit()
      t = $0; sub(/^  - type:[[:space:]]*/, "", t); sub(/[[:space:]]+$/, "", t)
      type = t; next
    }
    in_refs && /^    id:/ {
      v = $0; sub(/^    id:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      id = v; next
    }
    in_refs && /^    url:/ {
      v = $0; sub(/^    url:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      url = v; next
    }
    END { emit() }
  ' "$PLAN")

  if [[ -z "$refs_data" ]]; then
    echo "(none — PLAN.md has no refs: entries)"
  else
    # Group by type (first field). Preserve first-seen type order.
    types_order=()
    declare -A seen
    while IFS='|' read -r t id url; do
      [[ -z "$t" ]] && continue
      if [[ -z "${seen[$t]+x}" ]]; then
        types_order+=("$t")
        seen[$t]=1
      fi
    done <<< "$refs_data"

    for t in "${types_order[@]}"; do
      n=$(printf '%s\n' "$refs_data" | awk -F '|' -v tp="$t" '$1==tp {c++} END {print c+0}')
      echo "[$t] $n"
      while IFS='|' read -r rt rid rurl; do
        [[ "$rt" == "$t" ]] || continue
        if [[ -n "$rurl" ]]; then
          if [[ -n "$rid" ]]; then
            printf '  · %s → %s\n' "$rid" "$rurl"
          else
            printf '  · %s\n' "$rurl"
          fi
        elif [[ -n "$rid" ]]; then
          printf '  · id=%s\n' "$rid"
        fi
      done <<< "$refs_data"
    done
  fi
fi
