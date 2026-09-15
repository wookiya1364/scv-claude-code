# help — Mode B' — archive search

Read from `/scv:help` at "→ Mode B' (archive search)". Follow it, then return to the protocol where you left off.

> `<plugin root>` below means the directory two levels above this file (this file lives at
> `<plugin root>/protocols/help/`; the helper scripts live at `<plugin root>/scripts/`). Branch
> files are read as plain text, so no path placeholder is expanded here — derive the absolute
> path from where you read this file.

#### → Mode B' (archive search)

Skip Steps B0–B6 entirely. Instead:

1. Run `bash "<plugin root>/scripts/help.sh" --archive-index` and read its `ARCHIVE_INDEX:` block (`<folder> | <title> | <created_at>` per entry). If it shows `(empty)` or `(no archive yet)`, tell the user honestly and suggest `/scv:promote` to create the first plan. Stop.
2. Pick the 1–5 archives whose `<title>` / `<folder>` / `<created_at>` best match the user's question. Be conservative — fewer hits beat speculative ones.
3. For each picked archive, read `scv/archive/<folder>/PLAN.md` (only the picked ones — don't read all). Extract: one-sentence purpose · `refs:` links · `supersedes:` if present · final outcome (look at the `Approach Overview` / `Result` sections).
4. Print a compact summary in the resolved language. Format suggestion (one block per archive):

   ```
   • <folder>  ·  <created_at>
     <title>
     <one-sentence purpose>
     refs: <jira/linear/... if any>
     supersedes: <slug if any>
   ```

5. End with a single follow-up offer: `"Want to start a new plan based on one of these? Tell me which folder and I'll open it as a conversation seed."` If the user picks one, copy the relevant excerpts into a new `scv/conversations/<timestamp>-<slug>.md` and proceed as Mode B from Step B1.

Do not enter the long Mode B conversation loop here — Mode B' answers the question and stops.
