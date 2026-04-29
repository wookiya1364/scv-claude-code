---
name: ralph-prompt
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team"]
tags: [ralph, entrypoint]
standard_version: 1.0.0
merge_policy: preserve
---

# RALPH_PROMPT — <project name>

> Thin entry point for Ralph Loop. This file is **project-specific** and must be filled in. The spec source is the standard documents completed via `INTAKE.md`.
> **Prerequisite**: before filling this in, INTAKE.md Steps 1–7 must be complete and all required standard docs must have `status: active`.

## How to elicit

1. "What's the **Phase name** to focus on in the current iteration?" (e.g., "Phase 2 — voice core")
2. "Package manager?" (npm / pnpm / yarn / pip / uv / cargo …)
3. "Dev server command?" / "Build command?" / "Test command?" / "E2E command?" / "Install command?"
4. "Anything to be especially careful about this iteration — past failure causes, workarounds?"

## Completion criteria

- [ ] `focus_phase` written as a single line
- [ ] Every command field filled with a working command (or marked "n/a")
- [ ] `iteration_notes` records the current context

---

## Standard document locations

- `./INTAKE.md` — Dialogue protocol (don't modify)
- `./DOMAIN.md` — Domain
- `./ARCHITECTURE.md` — Architecture
- `./DESIGN.md` — UI/UX (if applicable)
- `./AGENTS.md` — AI agents (if applicable)
- `./TESTING.md` — Testing
- `./REPORTING.md` — Collab tool
- `./promote/*` — Promoted topic / plan documents

## Focus for this run

focus_phase: <TODO: e.g., "Phase 1 — Infrastructure">

iteration_notes: |
  <TODO: this iteration's context, gotchas, summary of past failures>

## Project-specific settings

package_manager: <TODO>
install_command: <TODO>
dev_command: <TODO>
build_command: <TODO>
test_command: <TODO>
e2e_command: <TODO>

## Verification tools

- Playwright config conventions and artifact paths — see `./TESTING.md`
- Chrome DevTools MCP conventions — also see `./TESTING.md`

## Reporting

- Pick collab tool via `.env` `NOTIFIER_PROVIDER`
- Reporting **must go through the `/scv:report <phase> <status>` slash command** only
- Channel mapping per `./REPORTING.md`

## Done criteria

1. Every Phase passes `./TESTING.md`'s success criteria
2. Right after each Phase, `/scv:report "<phase>" passed` returns `OK <thread_ref>`
3. (If applicable) AGENTS.md distribution-test / golden-set pass rate above threshold

## Additional references

<TODO: links, issues, prior decisions, external docs>
