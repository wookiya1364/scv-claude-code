---
description: "Declare that another repo needs corresponding development: write a handoff (+ decision + conversation) into the workspace root scv repo. Multi-repo (nested) only. Use whenever work in this repo implies a change another repo must make — not only when they type /scv:handoff. Never leave that dependency in prose; this command records it where the other repo will see it."
argument-hint: "[module] [to-repo and what they must build]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh:*)", "Write", "AskUserQuestion"]
---

# /scv:handoff

Producer side of the nested multi-repo loop. Use it AFTER you (in this child repo)
have made or planned a change that **requires corresponding development in another
repo** (e.g. FE shipped a button that needs a new BE endpoint). It records the
**explicit decision** + the **why** and propagates them to the shared workspace
**root** scv repo, so the other repo sees it on `git pull` (`/scv:status`).

This is an explicit, human/Claude Code-judged declaration — SCV never infers cross-repo
need from a code diff.

## Mode

Only meaningful when this repo is a workspace **CHILD** or **ROOT** (it has an
`SCV:WORKSPACE` block with a `root:` set — see `/scv:sync --join`). In a plain
**single** repo it is a no-op (prints a notice and exits). Run nothing manually to
check — the script resolves the mode itself.

## Language preference

Resolve the user's preferred language from `scv/scv_settings.json` `SCV_LANG`, then the latest
user message, then English. Use it for all user-facing prose. Keep technical
identifiers as-is (`repo_id`, `handoff_id`, skill invocations, paths).

## Plain language first

Skip this section only when `scv/scv_settings.json` sets `SCV_PLAIN_LANGUAGE=off`
(absent or any other value = on).

Answer shape — every time you explain something to the user:

1. First, 1–2 sentences. Lead with what the user gets.
   The cap is 2 unless `scv/scv_settings.json` sets `SCV_PLAIN_MAX_SENTENCES=<n>`
   (a positive integer) — then up to n.
2. Then one example — from the user's situation, or an everyday comparison.
3. No code values before the user asks: file paths, variable names, version
   numbers, setting values. Use the plain name instead ("the settings file",
   "last week's plan").
4. Detail comes after, and only when wanted. Offer it in one line.

Identifiers the user needs to act on — the next command to run, a file that
was created — stay exact, after the plain summary.

Bad: "The block landed in `scv_settings.example.json:154-161` and the stamp advanced
2.1.0 → 2.2.0."
Good: "Your settings example file is up to date. For example, the new 'effort'
setting now shows there. Want the exact lines?"

This governs everything the user reads: answers, questions, plans, progress
reports, summaries, and explanations of what went wrong.

## Protocol

1. **Identify the target + intent** from the user's argument and the current work:
   - `to_repo` — the repo id that must do corresponding dev (e.g. `be`, `ai`).
   - a short `slug` (3–5 kebab words), a one-line `title`.
   - `decision` — `needed` (default), `maybe`, or `not-needed` (record a no-op decision too, so the trail is complete).
   - optionally `from_slug` (the originating promote/archive slug) and a PR url.
   If `to_repo` or intent is ambiguous, ask one concise clarifying question.

2. **Author two short artifacts** (this is the real value — make them good, because
   they ARE the handoff; no synchronous conversation will happen):
   - **Body** (the WHAT): write to a temp file, e.g. `/tmp/scv-handoff-body.md`, with
     `## What <to_repo> must build` and `## Acceptance for the receiving repo`
     (concrete, testable bullets — these seed the consumer's TESTS.md).
   - **Why** (the rationale/conversation): write to `/tmp/scv-handoff-why.md`.

3. **Write + commit to the root** (commits locally; does NOT push):

   ```!
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh" write --to "<to_repo>" --slug "<slug>" --title "<title>" --decision "<needed|maybe|not-needed>" [--from-slug "<slug>"] [--ref-pr "<url>"] --body-file /tmp/scv-handoff-body.md --why-file /tmp/scv-handoff-why.md
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
   On a successful push, if a notifier is configured (`scv/scv_settings.json` `NOTIFIER_PROVIDER` =
   slack|discord, with a channel), SCV best-effort pings the team channel so the
   other repo's owner knows to pull. No notifier configured → silent no-op.

5. **Summarize**: the `HANDOFF_ID`, the target repo, and the next step for the
   receiver — *"In the `<to_repo>` repo: `git pull` the root, then `/scv:status`
   shows it; `/scv:promote` from the handoff, then `/scv:codegen`."*

## Monorepo (nested scv) — optional module target

When the umbrella and its modules live in one git repo, you can address a module
without `cd`-ing into it by giving its dir as the **leading** argument:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh" "<module>" write --to "<to_repo>" --slug "<slug>" --title "<title>" …
```

e.g. `handoff.sh fe write …` operates on `fe/scv` exactly as if run from inside
`fe/`. Omit the module to use the current directory's `scv/` — single-repo and
`cd`-into-child behavior is unchanged (byte-identical). The same optional
leading module arg works for `list` / `adopt` / `mark` / `push`.

> **Reserved names.** The leading arg is only peeled when it is NOT a subcommand
> keyword. So a module directory named exactly `write` / `push` / `list` /
> `adopt` / `mark` cannot be reached by the leading-arg form (the subcommand
> wins) — address such a module by `cd`-ing into it instead. Keep module dir
> names distinct from these keywords (the `FE` / `BE` / `AI` convention already
> is).

## Notes

- Fan-out to multiple repos = run once per target (one handoff file each; addressing stays 1:1).
- The decision + conversation are committed in the root repo (durable, cross-repo visible) — distinct from the single repo's own committed `scv/conversations/` / `scv/DECISIONS.md` (v0.22.0+), which stay repo-local.
- Staging is explicit-path only; the command never runs `git add -A`.
