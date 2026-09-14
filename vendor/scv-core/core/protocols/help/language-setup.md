# help — First-time language setup

Read from `/scv:help` at "First-time language setup". Follow it, then return to the protocol where you left off.

### First-time language setup (only when `scv/scv_settings.json` `SCV_LANG` is unset)

Ask this question exactly once:

```
Ask one question (default: option [1] English):
  Question: "Which language do you prefer for SCV output?"
  options:
  [1] "English"
      description: "All SCV skill invocation output (descriptions, prompts, summaries) is in English. Recommended default for global usage."
  [2] "한국어 (Korean)"
      description: "모든 SCV Claude Code 스킬 출력 (설명, 프롬프트, 요약) 을 한국어로 응답합니다."
  [3] "日本語 (Japanese)"
      description: "すべての SCV Claude Code skill 出力 (説明・プロンプト・要約) を日本語で応答します。"
  [4] "Other — type a language"
      description: "Pick this for any other language (Spanish, French, German, etc.). After selecting, you will be prompted to type the language name."
```

After the user picks:
- [1] English → store `SCV_LANG=english` in `scv/scv_settings.json`
- [2] Korean → store `SCV_LANG=korean`
- [3] Japanese → store `SCV_LANG=japanese`
- [4] Other → ask a follow-up free-text question ("Which language? e.g., spanish, french, german") and store the lowercase value as `SCV_LANG=<value>`.

Write it with the Core script, which creates the settings file when absent and leaves every
unrelated line byte for byte:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/settings-set.sh" SCV_LANG=<value>
```

Do not hand-edit the settings file for this. The script is what makes the write legible to
the workspace guard — and this question is asked before any other helper runs, so
an editor-tool write here would be the first thing a fresh project ever attempts.

From this point on, use the chosen language for all user-facing output in this and future SCV skills.
