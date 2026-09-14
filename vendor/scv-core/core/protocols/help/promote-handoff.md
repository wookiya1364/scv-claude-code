# help — Steps B3–B6 — enough information, promote hand-off, keep talking, free-form

Read from `/scv:help` at "Step B3 — "Enough information" signal". Follow it, then return to the protocol where you left off.

#### Step B3 — "Enough information" signal

You decide when the three goals (goal / scope / acceptance) are clear enough. **Be soft, not strict**: if scope is mostly clear and there's at least one concrete acceptance criterion, that's enough — the user can refine more during `/scv:promote`.

**The features/acceptance that come out of this conversation are the minimum requirement.** When you promote, each becomes a **detailed TESTS.md scenario** — that set equals what the PR ships. You may add supplementary tests on top (e.g. unit tests), but never author TESTS that fall below the user-stated features. (See `scv/PROMOTE.md` → "TESTS.md minimum requirements".)

Also offer the choice when:
- The user asks "is this enough yet?" / "should we move forward?"
- 8+ turns have happened (sanity cap — don't let it drag on forever)
- The user explicitly says "let's promote" / "make the plan"

Ask the user for confirmation:

```
Question: "Looks like we have enough to draft a plan. How would you like to proceed?"
options:
[1] "Yes — draft PLAN.md + TESTS.md now"
    description: "I run /scv:promote with this conversation as the input. The conversation file stays in scv/conversations/ (committed, redaction-filtered). PLAN.md / TESTS.md land in scv/promote/<slug>/ and are ready to commit."

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
- (No raw/ copy) — `/scv:promote` reads from `scv/conversations/<file>` into PLAN.md context.

**Choice [2]** — first copy:
```bash
TARGET="scv/raw/$(date +%Y%m%d)-$(git config user.name | tr '[:upper:] ' '[:lower:]-')-<slug>.md"
cp scv/conversations/<file> "$TARGET"
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
