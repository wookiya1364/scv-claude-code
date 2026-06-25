---
description: "Declare that another repo needs corresponding development: write a handoff (+ decision + conversation) into the workspace root scv repo. Multi-repo (nested) only."
argument-hint: "[to-repo and what they must build]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh:*)", "Write", "AskUserQuestion"]
model: sonnet
---

# /scv:handoff

Producer side of the nested multi-repo loop. Use it AFTER you (in this child repo)
have made or planned a change that **requires corresponding development in another
repo** (e.g. FE shipped a button that needs a new BE endpoint). It records the
**explicit decision** + the **why** and propagates them to the shared workspace
**root** scv repo, so the other repo sees it on `git pull` (`/scv:status`).

This is an explicit, human/Claude-judged declaration — SCV never infers cross-repo
need from a code diff.

## Mode

Only meaningful when this repo is a workspace **CHILD** or **ROOT** (it has an
`SCV:WORKSPACE` block with a `root:` set — see `/scv:sync --join`). In a plain
**single** repo it is a no-op (prints a notice and exits). Run nothing manually to
check — the script resolves the mode itself.

## Language preference

Resolve the user's preferred language (settings.json `language` → `.env` `SCV_LANG`
→ detect from last message → English) and use it for all user-facing prose. Keep
technical identifiers as-is (`repo_id`, `handoff_id`, slash commands, paths).

## Protocol

1. **Identify the target + intent** from the user's argument and the current work:
   - `to_repo` — the repo id that must do corresponding dev (e.g. `be`, `ai`).
   - a short `slug` (3–5 kebab words), a one-line `title`.
   - `decision` — `needed` (default), `maybe`, or `not-needed` (record a no-op decision too, so the trail is complete).
   - optionally `from_slug` (the originating promote/archive slug) and a PR url.
   If `to_repo` or intent is ambiguous, ask ONE clarifying question (AskUserQuestion).

2. **Author two short artifacts** (this is the real value — make them good, because
   they ARE the handoff; no synchronous conversation will happen):
   - **Body** (the WHAT): write to a temp file, e.g. `/tmp/scv-handoff-body.md`, with
     `## What <to_repo> must build` and `## Acceptance for the receiving repo`
     (concrete, testable bullets — these seed the consumer's TESTS.md).
   - **Why** (the rationale/conversation): write to `/tmp/scv-handoff-why.md`.

3. **Write + commit to the root** (commits locally; does NOT push):

   ```!
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh" write --to <to_repo> --slug <slug> --title "<title>" --decision <needed|maybe|not-needed> [--from-slug <slug>] [--ref-pr <url>] --body-file /tmp/scv-handoff-body.md --why-file /tmp/scv-handoff-why.md
   ```

   If it prints a graceful-degrade message (root unreachable), tell the user the
   handoff could not be propagated yet and that local work is unaffected — retry
   when the root is reachable.

4. **Push — ask first, every time.** Show the user one line:
   *"Push this handoff to the workspace root (`<root>`)? It becomes visible to the
   other repo on their next pull."* Only on explicit yes:

   ```!
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh" push
   ```

   Never push without that explicit consent (no standing license from a prior push).
   On a successful push, if a notifier is configured (`.env` `NOTIFIER_PROVIDER` =
   slack|discord, with a channel), SCV best-effort pings the team channel so the
   other repo's owner knows to pull. No notifier configured → silent no-op.

5. **Summarize**: the `HANDOFF_ID`, the target repo, and the next step for the
   receiver — *"In the `<to_repo>` repo: `git pull` the root, then `/scv:status`
   shows it; `/scv:promote` from the handoff, then `/scv:codegen`."*

## Notes

- Fan-out to multiple repos = run once per target (one handoff file each; addressing stays 1:1).
- The decision + conversation are committed in the root repo (durable, cross-repo visible) — distinct from the gitignored local `scv/.conversations/`.
- Staging is explicit-path only; the command never runs `git add -A`.
