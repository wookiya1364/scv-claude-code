---
description: "Show SCV workflow + diagnose project + recommend next step. With an argument, enter conversation mode — talk through your idea naturally and SCV will offer to promote when ready."
argument-hint: "[\"natural-language idea (optional)\"]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/help.sh:*)", "Bash(mkdir:*)", "Bash(cat:*)", "Bash(grep:*)", "Bash(echo:*)", "Bash(test:*)", "Bash(date:*)", "AskUserQuestion", "Read", "Write", "Edit"]
---

# /scv:help

Two modes — picked automatically by whether you passed a free-form argument.

## Mode A — Diagnosis (no argument)

`/scv:help` with no argument: print SCV overview + diagnose current project + recommend next step. Used when you don't know what to do or want a status check.

## Mode B — Conversation (with argument, v0.9.0+)

`/scv:help "I want to add a refund button"` (or any free-form idea): enter **conversation mode**. Claude talks with you to refine your raw idea into a concrete plan, persists the conversation to disk so you can pick it up later, and offers to promote when there's enough information for `PLAN.md + TESTS.md`.

This mode is the entry point for **adoption mode without raw materials** — you have an idea but nothing in `scv/raw/` yet.

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

Parse the helper output:
- `ARG_CONVERSATION:` line — the free-form argument (empty = Mode A diagnosis, non-empty = Mode B conversation)
- `UNFINISHED_CONVERSATIONS:` line — files at top level of `scv/.conversations/` (active = NOT yet archived). Empty list shown as `(none)`.

Then branch:

### If `ARG_CONVERSATION:` is empty → Mode A (diagnosis)

Re-present the rest of the script's output in the resolved language: translate descriptions, recommended next-step explanations, and section headers. Keep slash command names (`/scv:help`, `/scv:promote`, …), file paths, and SCV technical terms (`promote`, `archive`, `orphan branch`, `epic`, `supersedes`) as-is. **If `UNFINISHED_CONVERSATIONS:` is non-empty**, also list them in your output: "You have N unfinished conversation(s). Run `/scv:help` with an idea (e.g., `/scv:help \"continue the refund button\"`) to resume — or start a new one."

### If `ARG_CONVERSATION:` is non-empty → Mode B (conversation)

#### Step B0 — Resume vs new

If `UNFINISHED_CONVERSATIONS:` lists ≥1 file, fire `AskUserQuestion`:

```
Question: "You have unfinished conversation(s). What now?"
options:
[1] "Resume the most recent: <basename of latest file>"
    description: "Continue from where you stopped. The file is read into context, your new argument is appended as a follow-up turn, and we keep refining."
[2] "Start a new conversation"
    description: "Create a fresh conversation file. The unfinished one(s) stay in scv/.conversations/ — they aren't deleted."
[3] "List all unfinished and pick"
    description: "Show every active file with its title + last update, then choose."
```

If `UNFINISHED_CONVERSATIONS: (none)`, skip Step B0 and create a new conversation file directly.

#### Step B1 — Create / open the conversation file

For a **new** conversation:
- Slug: derive from the user's argument (3–5 lowercase kebab-case words, e.g., `"I want to add a refund button"` → `refund-button`).
- Filename: `scv/.conversations/<YYYYMMDD-HHMMSS>-<slug>.md`. Use `date +%Y%m%d-%H%M%S`.
- Frontmatter:
  ```yaml
  ---
  slug: <slug>
  started_at: <ISO datetime>
  status: active                  # active | promoted | archived
  promoted_to: null               # path to scv/raw/<...> or scv/promote/<...> when /scv:help opens promote
  ---
  ```
- First turn: copy the user's `ARG_CONVERSATION` as the opening user message. Append Claude's response.

For a **resume**:
- Read the existing file (frontmatter + previous turns) into context.
- Append `ARG_CONVERSATION` as a new user turn. Continue from there.

If `scv/.conversations/` does not exist, create it (`mkdir -p scv/.conversations`). The directory is gitignored — local to this user's machine.

#### Step B2 — Conversation loop

Engage the user in natural dialog. Goals (your judgment, not strict):

- **Goal** — what feature / change is wanted, in one sentence
- **Scope** — what's in / out of scope (e.g., "full refund only, no partial" / "Stripe only, not other gateways")
- **Acceptance** — at least one concrete behavior that can be verified (e.g., "API returns 403 if order older than 7 days")

Ask clarifying questions when something is ambiguous. **Don't dump all questions at once** — pick the most blocking unknown and ask. Wait for answer. Repeat.

After each turn, **append to the conversation file**:

```markdown
## Turn <N> — <ISO timestamp>

**User**: <user's message>

**Claude**: <your response, including any clarifying questions>
```

Use `Edit` (append) — never overwrite. The file persists turn-by-turn so the user can quit anytime without losing progress.

#### Step B3 — "Enough information" signal

You decide when the three goals (goal / scope / acceptance) are clear enough. **Be soft, not strict**: if scope is mostly clear and there's at least one concrete acceptance criterion, that's enough — the user can refine more during `/scv:promote`.

Also offer the choice when:
- The user asks "is this enough yet?" / "should we move forward?"
- 8+ turns have happened (sanity cap — don't let it drag on forever)
- The user explicitly says "let's promote" / "make the plan"

Fire `AskUserQuestion`:

```
Question: "Looks like we have enough to draft a plan. How would you like to proceed?"
options:
[1] "Yes — draft PLAN.md + TESTS.md now"
    description: "I run /scv:promote with this conversation as the input. The conversation file stays in scv/.conversations/ (gitignored, your local). PLAN.md / TESTS.md land in scv/promote/<slug>/ and are ready to commit."

[2] "Yes — and also copy this conversation into scv/raw/ for team traceability"
    description: "Same as [1], plus the conversation is copied to scv/raw/<YYYYMMDD>-<author>-<slug>.md so teammates can see what you discussed before the plan was drafted. Pick this when your team values raw thinking history."

[3] "No — keep talking"
    description: "Continue the conversation. We'll re-check at the next natural pause."

[4] (free-form) "Other"
    description: "Examples: 'pause this for now, I'll come back later' / 'change the slug to <new>' / 'discard this conversation'."
```

#### Step B4 — On choice [1] or [2] — promote

**Update the conversation file's frontmatter**:
```yaml
status: promoted
promoted_to: scv/promote/<YYYYMMDD>-<author>-<slug>/
```

**Choice [1]** — call `/scv:promote` directly. Pass the conversation file path so promote.md can read it as the source material:
- (No raw/ copy) — `/scv:promote` reads from `scv/.conversations/<file>` into PLAN.md context.

**Choice [2]** — first copy:
```bash
TARGET="scv/raw/$(date +%Y%m%d)-$(git config user.name | tr '[:upper:] ' '[:lower:]-')-<slug>.md"
cp scv/.conversations/<file> "$TARGET"
```
Then call `/scv:promote`. The raw/ copy lets teammates see the conversation history.

After `/scv:promote` finishes, print one-line summary: "Conversation `<file>` is now linked to plan `<slug>`. Implement next: `/scv:work <slug>`."

#### Step B5 — On choice [3] — keep talking

Continue the loop. Don't immediately re-ask "enough yet?" — wait for natural pause (3+ more turns or explicit user signal).

#### Step B6 — On choice [4] — free-form

Parse the user's intent:
- "pause for now" → leave the file as `status: active`. Tell the user: "Saved. Run `/scv:help "..."` later to resume."
- "discard" → ask once more for confirmation, then delete the file.
- "change slug" → rename the file accordingly.
- Other → engage in natural conversation.

## Final notes — both modes

The script's stdout is in English (technical output). In Mode A, re-present its content in the resolved language. In Mode B, the entire conversation should be in the resolved language — but technical identifiers (file paths, slash command names, frontmatter keys, env var names like `SCV_LANG`) always stay as-is.
