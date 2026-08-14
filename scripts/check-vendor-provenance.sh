#!/usr/bin/env bash
# Vendor gate — the vendored Core tree is written by the sync bot, not by hand.
#
# Sibling of check-provenance.sh, same shape and the same escape hatch, guarding
# a different thing: that one asks where a code change came from, this one asks
# who moved the pinned Core.
#
# Why it exists. Every wrapper carries a copy of Core under vendor/scv-core/, and
# a bot proposes each new pin as its own pull request. Vendoring by hand inside
# some other branch — a release branch, most temptingly, since the version bump
# is right there — produces a tree that looks correct and is: the bot's pull
# request then arrives already satisfied and gets closed as redundant. That is
# the visible cost. The invisible one is that the two paths do not do the same
# work. The bot resolves an immutable release artifact and records both the
# canonical and the materialized hash; a hand copy records whatever was in the
# working tree, which is the same thing only when the working tree happened to
# be clean. Nothing downstream can tell the two apart afterwards.
#
# So hand-vendoring stays possible — a Core contract change can genuinely need
# it — but it has to be said out loud, in the title, with a reason.
#
# Inputs (environment; a CI job supplies them):
#   BASE_REF   target branch name
#   HEAD_REF   source branch name
#   PR_TITLE   pull request title
#   BASE_SHA   optional; merge base to diff from (else derived from origin/BASE_REF)
#   SCV_VENDOR_SYNC_BRANCH  optional; glob for the bot's branch (default chore/core-*)

set -uo pipefail

BASE_REF="${BASE_REF:-}"
HEAD_REF="${HEAD_REF:-}"
PR_TITLE="${PR_TITLE:-}"
SYNC_BRANCH="${SCV_VENDOR_SYNC_BRANCH:-chore/core-*}"

note() { printf '%s\n' "$1"; }
pass() { note "$1"; exit 0; }
deny() { printf '::error::%s\n' "$1" >&2; printf '%s\n' "$1"; exit 1; }

# --- exemption 1: the release chain ----------------------------------------
# develop→stage and stage→main carry every change already merged into develop,
# including whatever moved the vendor tree. Re-asking here would block the
# promotion of a pin this same check already cleared on the way in.
case "$BASE_REF" in
  stage|main) pass "vendor: release-chain pull request into ${BASE_REF} — exempt." ;;
esac

# --- exemption 2: the sync bot, whose job this is ---------------------------
# shellcheck disable=SC2254  # the glob is the point
case "$HEAD_REF" in
  $SYNC_BRANCH) pass "vendor: automated Core sync branch ${HEAD_REF} — exempt." ;;
esac

# --- exemption 3: a declared exception, with a stated reason ----------------
# `[manual-vendor: reason]`, deliberately the same form as [no-plan: reason] in
# check-provenance.sh — one convention to learn, not two. An empty marker is
# refused for the same reason there: the reason is the entire point of it.
if printf '%s' "$PR_TITLE" | grep -qE '\[manual-vendor:[[:space:]]*[^][:space:]][^]]*\]'; then
  reason="$(printf '%s' "$PR_TITLE" | sed -n 's/.*\[manual-vendor:[[:space:]]*\([^]]*\)\].*/\1/p')"
  pass "vendor: declared exception — ${reason}"
fi
if printf '%s' "$PR_TITLE" | grep -qE '\[manual-vendor[]:]'; then
  deny "This pull request carries a [manual-vendor] marker with no reason. Write it as [manual-vendor: why the bot could not do this] — the reason is the point of the marker."
fi

# --- the diff ---------------------------------------------------------------
if [[ -n "${BASE_SHA:-}" ]]; then
  base="$BASE_SHA"
elif [[ -n "$BASE_REF" ]] && git rev-parse --verify --quiet "origin/$BASE_REF" >/dev/null; then
  base="$(git merge-base "origin/$BASE_REF" HEAD 2>/dev/null)"
fi
if [[ -z "${base:-}" ]]; then
  pass "vendor: no merge base available (shallow checkout?) — skipping."
fi

changed="$(git diff --name-only "$base"...HEAD 2>/dev/null)"

# --- the check --------------------------------------------------------------
# Matched by shape, not by a hardcoded path: wrappers nest the vendor tree at
# different depths, and naming them here would make this file host-specific.
touched="$(printf '%s\n' "$changed" | grep -E '(^|/)vendor/scv-core/' || true)"

[[ -n "$touched" ]] || pass "vendor: the pinned Core tree is untouched — exempt."

count="$(printf '%s\n' "$touched" | grep -c . || true)"
sample="$(printf '%s\n' "$touched" | head -5)"

deny "This pull request rewrites the vendored Core tree (${count} file(s)) on a branch that is not the sync bot's.

${sample}

The bot opens its own pull request for each Core release, resolving the published
artifact and recording both hashes. Merge that one instead, then bump the wrapper
version in a separate change — the two are separate decisions and separate diffs.

If the bot genuinely cannot do it, say so in the title: [manual-vendor: <reason>]."
