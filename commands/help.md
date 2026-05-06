---
description: "Show the SCV workflow, commands, current project status, and the recommended next step. Run this first when you don't know what to do."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/help.sh:*)", "Bash(cat:*)", "Bash(grep:*)", "Bash(echo:*)", "Bash(test:*)"]
---

# /scv:help

Print an overview of SCV, the plugin's commands, a diagnosis of the current project, and what to do next.

## Language preference — resolve FIRST, before any user-facing output

Decide which language to use for ALL output below (descriptions, headings, AskUserQuestion text, summaries). Apply this priority:

1. **`~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key.** Claude Code's official setting. Values are language names like `"korean"`, `"english"`, `"japanese"`. If present, use that language and skip the rest.
2. **Project `.env` — `SCV_LANG`** (the SCV plugin's own setting, written by the first-time setup below). If present, use that.
3. **Auto-detect from the user's most recent message.** If they wrote in a recognizable language, use it.
4. **Default to English.**

Technical identifiers (file paths, slash command names, frontmatter keys, env var names like `SCV_LANG`) always stay as-is — never translate them.

### First-time language setup (only when BOTH `settings.json` `language` AND `.env` `SCV_LANG` are unset)

Run this AskUserQuestion exactly once:

```
AskUserQuestion (default: option [1] English):
  Question: "Which language do you prefer for SCV output?"
  options:
  [1] "English"
      description: "All SCV slash command output (descriptions, prompts, summaries) is in English. Recommended default for global usage."
  [2] "한국어 (Korean)"
      description: "모든 SCV 슬래시 명령어 출력 (설명, 프롬프트, 요약) 을 한국어로 응답합니다."
  [3] "日本語 (Japanese)"
      description: "すべての SCV スラッシュコマンド出力 (説明・プロンプト・要約) を日本語で応答します。"
  [4] "Other — type a language"
      description: "Pick this for any other language (Spanish, French, German, etc.). After selecting, you will be prompted to type the language name."
```

After the user picks:
- [1] English → store `SCV_LANG=english` in project `.env`
- [2] Korean → store `SCV_LANG=korean`
- [3] Japanese → store `SCV_LANG=japanese`
- [4] Other → ask a follow-up free-text question ("Which language? e.g., spanish, french, german") and store the lowercase value as `SCV_LANG=<value>`.

If project `.env` does not exist, create it with just that line. If it exists, append the line (without disturbing existing entries).

From this point on, use the chosen language for all user-facing output in this and future SCV commands.

## Run the help script

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/help.sh" $ARGUMENTS
```

The script's stdout is in English (technical output). Re-present its content to the user in the resolved language: translate descriptions, recommended next-step explanations, and section headers. Keep slash command names (`/scv:help`, `/scv:promote`, …), file paths, and SCV technical terms (`promote`, `archive`, `orphan branch`, `epic`, `supersedes`) as-is.
