---
description: "Detect missing SCV system dependencies (git, gh, glab, curl, jq, ffmpeg, python3) and either show OS-specific install commands or run them. graphify (Claude Code skill) is detected separately and links to its install guide."
argument-hint: ""
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/install-deps.sh:*)"
  - "AskUserQuestion"
---

# /scv:install-deps

Detect SCV's external CLI dependencies on the current machine and help the user install whatever is missing.

## Language preference

Resolve the user's preferred language with this priority, then use it for ALL user-facing output (AskUserQuestion text, summaries):

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official).
2. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers (tool names like `gh`, `glab`, `ffmpeg`, command names, file paths, env var names) stay as-is. If both `settings.json language` and `.env SCV_LANG` are unset, suggest `/scv:help` once to lock the preference (don't block — fall back to auto-detect / English for now).

## Step 0 — Run --check

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/install-deps.sh" --check
```

Parse the output:
- `OS detected:` and `Package manager:` lines tell you the user's environment.
- `Dependency check:` block shows each tool with `[✓]` (installed), `[✗]` (missing — required/recommended tier), or `[△]` (missing — optional tier, graceful degrade).
- The `Result:` line at the end is one of:
  - `All deps installed.` — exit 0, nothing to do.
  - `All required tools installed. Some recommended/optional missing — ...` — exit 0, partial.
  - `REQUIRED tools missing: ...` — exit 1.

## Step 1 — Decide what to do

If the `Result:` line says **`All deps installed`** AND graphify is present:
- Tell the user "All SCV dependencies are installed." in their preferred language.
- Stop.

Otherwise, fire **one** AskUserQuestion to decide next action:

```
Question: "<n> dependencies are missing. What would you like to do?"
  (where <n> is the missing count from --check output)

Options:
[1] "Install now"
    description:
    "Run `install-deps.sh --install` to actually install the missing system tools.
     - Linux / macOS: sudo password may be prompted for apt / dnf / pacman.
     - Windows: winget will open its own confirmation dialog per package.
     - graphify (Claude Code skill) is NOT installed by this command — it has a
       different distribution channel. See https://github.com/safishamsi/graphify
       and place SKILL.md at ~/.claude/skills/graphify/."

[2] "Just print the install commands (I'll run them myself)"
    description:
    "No installation is performed. The output of --check already shows the
     exact commands for the detected OS / package manager — copy and run them
     in your terminal as you see fit. Use this if you prefer reviewing each
     step or you don't want sudo to be invoked from a slash command."

[3] "Cancel — do nothing for now"
    description:
    "Exit without changes. SCV will keep running in graceful-degrade mode for
     missing optional tools (ffmpeg / python3). For missing required tools
     (git) or platform tools (gh / glab) the related slash commands may fail
     until installed."
```

Answer handling:

- **[1] Install now**:
  ```!
  "${CLAUDE_PLUGIN_ROOT}/scripts/install-deps.sh" --install
  ```
  After it returns, summarize the result in the user's language: how many tools installed, any failures, whether `--check` should be re-run for verification (you can offer to do so but don't auto-run).

- **[2] Print only**: Tell the user the commands are already shown in Step 0's output, and remind them which OS-specific block applies. No further script invocation.

- **[3] Cancel**: One-line confirmation. Stop.

## Notes

- **graphify is NOT auto-installed.** It is a Claude Code skill (not a system CLI) with a different distribution channel. The script's output and Step 1's description always link to https://github.com/safishamsi/graphify so the user can install it manually.
- **Idempotency**: `--check` and `--install` are safe to re-run. `--install` skips already-installed tools.
- **Verification scope**: install commands are documented per upstream packaging guides. The repository author has end-to-end-verified Linux/apt only. macOS / Windows / other Linux distros are best-effort — if a command needs adjustment, open an issue on the SCV repo.

## Never

- Auto-run `--install` without going through the AskUserQuestion. The user must explicitly choose `[1] Install now`.
- Modify the user's `~/.claude/skills/` directory or attempt to download graphify automatically.
- Suggest `sudo` commands for Windows (winget runs as user; admin elevation is per-package via the system dialog).
