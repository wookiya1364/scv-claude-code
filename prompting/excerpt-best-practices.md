<!--
Source: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices.md
Fetched: 2026-11-11
Copyright: Anthropic PBC. Verbatim copy of the official documentation, kept offline for SCV help. Do not edit; run prompting/refresh.sh to update.
Excerpt: only the sections named in the excerpt list, each copied verbatim from this source.
-->
### Be clear and direct

Claude responds well to clear, explicit instructions. Being specific about the output you want can help enhance results. If you want Claude to do more than the task strictly requires, explicitly request it rather than relying on the model to infer this from vague prompts.

Think of Claude as a brilliant but new employee who lacks context on your norms and workflows. The more precisely you explain what you want, the better the result.

**Key test:** Show your prompt to a colleague with minimal context on the task and ask them to follow it. If they’d be confused, Claude will be too.

* Be specific about the output format and constraints you want.
* Provide instructions as sequential steps using numbered lists or bullet points when the order or completeness of steps matters.

<Accordion title="Example: Creating an analytics dashboard" defaultOpen>
  **Less effective:**

  ```text wrap
  Create an analytics dashboard
  ```

  **More effective:**

  ```text wrap
  Create an analytics dashboard. Include as many relevant features and interactions as possible. Go beyond the basics to create a fully-featured implementation.
  ```
</Accordion>

### Add context to improve performance

Providing context or motivation behind your instructions, such as explaining to Claude why such behavior is important, can give Claude more information about your goals and help it deliver more targeted responses.

<Accordion title="Example: Formatting preferences" defaultOpen>
  **Less effective:**

  ```text wrap
  NEVER use ellipses
  ```

  **More effective:**

  ```text wrap
  Your response will be read aloud by a text-to-speech engine, so never use ellipses since the text-to-speech engine will not know how to pronounce them.
  ```
</Accordion>

Claude can generalize from the explanation.

### Tool usage

Claude’s latest models are trained for precise instruction following and benefit from explicit direction to use specific tools. If you say “can you suggest some changes,” Claude will sometimes provide suggestions rather than implementing them, even if making changes might be what you intended. To learn how to define tools and troubleshoot tool triggering, see [Tool use with Claude](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview).

For Claude to take action, be more explicit:

<Accordion title="Example: Explicit instructions" defaultOpen>
  **Less effective (Claude will only suggest):**

  ```text wrap
  Can you suggest some changes to improve this function?
  ```

  **More effective (Claude will make the changes):**

  ```text wrap
  Change this function to improve its performance.
  ```

  Or:

  ```text wrap
  Make these edits to the authentication flow.
  ```
</Accordion>

To make Claude more proactive about taking action by default, you can add this to your system prompt:

```text Sample prompt for proactive action wrap
<default_to_action>
By default, implement changes rather than only suggesting them. If the user's intent is
unclear, infer the most useful likely action and proceed, using tools to discover any
missing details instead of guessing. Try to infer the user's intent about whether a tool
call (e.g., file edit or read) is intended or not, and act accordingly.
</default_to_action>
```

On the other hand, if you want the model to be more hesitant by default, less prone to starting implementations immediately, and only take action if requested, you can steer this behavior with a prompt such as the following:

```text Sample prompt for conservative action wrap
<do_not_act_before_instructions>
Do not jump into implementation or change files unless clearly instructed to make
changes. When the user's intent is ambiguous, default to providing information, doing
research, and providing recommendations rather than taking action. Only proceed with
edits, modifications, or implementations when the user explicitly requests them.
</do_not_act_before_instructions>
```

Claude Opus 4.5 and Claude Opus 4.6 are also more responsive to the system prompt than previous models. If your prompts were designed to reduce undertriggering on tools or skills, these models might now overtrigger. The fix is to soften any aggressive language. Where you might have said “CRITICAL: You MUST use this tool when...,” you can use more normal prompting such as “Use this tool when...” instead.

### Balancing autonomy and safety

Without guidance, Claude Opus 4.6 might take actions that are difficult to reverse or affect shared systems, such as deleting files, force-pushing, or posting to external services. If you want Claude Opus 4.6 to confirm before taking potentially risky actions, add guidance to your prompt:

```text Sample prompt wrap
Consider the reversibility and potential impact of your actions. You are encouraged to
take local, reversible actions like editing files or running tests, but for actions that
are hard to reverse, affect shared systems, or could be destructive, ask the user before
proceeding.

Examples of actions that warrant confirmation:
- Destructive operations: deleting files or branches, dropping database tables, rm -rf
- Hard to reverse operations: git push --force, git reset --hard, amending published commits
- Operations visible to others: pushing code, commenting on PRs/issues, sending
messages, modifying shared infrastructure

When encountering obstacles, do not use destructive actions as a shortcut. For example,
don't bypass safety checks (e.g. --no-verify) or discard unfamiliar files that may be
in-progress work.
```

### Research and information gathering

Claude’s latest models can find and synthesize information from multiple sources effectively. For optimal research results:

1. **Provide clear success criteria:** Define what constitutes a successful answer to your research question.

2. **Encourage source verification:** Ask Claude to verify information across multiple sources.

3. **For complex research tasks, use a structured approach:**

```text Sample prompt for complex research wrap
Search for this information in a structured way. As you gather data, develop several
competing hypotheses. Track your confidence levels in your progress notes to improve
calibration. Regularly self-critique your approach and plan. Update a hypothesis tree or
research notes file to persist information and provide transparency. Break down this
complex research task systematically.
```

This structured approach helps Claude work through large corpora methodically and iteratively critique its findings.

### Overeagerness

Claude Opus 4.5 and Claude Opus 4.6 have a tendency to overengineer by creating extra files, adding unnecessary abstractions, or building in flexibility that wasn’t requested. If you’re seeing this undesired behavior, add specific guidance to keep solutions minimal.

For example:

```text Sample prompt to minimize overengineering wrap
Avoid over-engineering. Only make changes that are directly requested or clearly
necessary. Keep solutions simple and focused:

- Scope: Don't add features, refactor code, or make "improvements" beyond what was
asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need
extra configurability.

- Documentation: Don't add docstrings, comments, or type annotations to code you didn't
change. Only add comments where the logic isn't self-evident.

- Defensive coding: Don't add error handling, fallbacks, or validation for scenarios
that can't happen. Trust internal code and framework guarantees. Only validate at system
boundaries (user input, external APIs).

- Abstractions: Don't create helpers, utilities, or abstractions for one-time
operations. Don't design for hypothetical future requirements. The right amount of
complexity is the minimum needed for the current task.
```

