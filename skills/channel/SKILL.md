---
name: channel
description: "Switch the installed SCV between the dev, stage and prod channels — try new work before it is released, then switch back. No argument shows the current channel. Use whenever the user wants to try the development or staging version of SCV, or go back to the released one — not only when they type /scv:channel."
argument-hint: "[dev | stage | prod]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/channel.sh:*)"]
---

# /scv:channel

A channel is where the installed SCV comes from: **dev** (the newest work on the develop branches), **stage**
(the staging branches) or **prod** (the released version — the default). One channel is installed at a time;
switching swaps it. Full rule: Core `protocols/channel.md`.

First show the current channel (changes nothing):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/channel.sh"
```

It prints `CHANNEL: <dev|stage|prod> <version>`.

- The user named a channel in plain words ("개발 버전으로", "back to the release") → still confirm it with
  one `AskUserQuestion`, the named channel first and marked recommended, plus "keep the current one".
- No channel named → ask with `AskUserQuestion`: the three channels minus the current one, prod first when
  the current channel is not prod, plus "keep the current one". Each option says what it installs.
- Picking is the confirmation. "Keep the current one" → stop.

Then switch:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/channel.sh" "<picked channel>"
```

Report in plain words, in the user's language: the channel and version before and after ("prod 0.70.4 →
dev 0.70.5-dev.abc1234"), or "already on <channel>". Relay every `NEXT:` line as it is — the user runs
`/reload-plugins` (or opens a new session); this command cannot run it.

`RESULT: failed …` is a failure: name the failed step, never report it as switched. `RESULT: restored <channel>`
means the swap failed after the old one was removed and the old channel was put back. `branch-missing` means
that channel has not been built yet — nothing was changed.

Never edit `~/.claude/plugins` by hand or touch project files.
