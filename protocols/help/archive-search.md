# help — Mode B' — archive search

Read from `/scv:help` at "→ Mode B' (archive search)". Follow it, then return to the protocol where you left off.

> `<plugin root>` below means the directory two levels above this file (this file lives at
> `<plugin root>/protocols/help/`; the helper scripts live at `<plugin root>/scripts/`). Branch
> files are read as plain text, so no path placeholder is expanded here — derive the absolute
> path from where you read this file.

#### → Mode B' (archive search)

Skip Steps B0–B6 entirely. Instead:

1. **Sweep the bodies first** (v0.53.0+) — titles alone miss most of the answer. Take the
   distinctive words out of the user's question and run:

   ```bash
   bash "<plugin root>/scripts/archive-search.sh" <word> <word> …
   ```

   It reads archived plans and their tests, architecture and archive records, consumed raw
   material, conversations (the archived sub-folder included) and the decision log — one
   pass, digested output, no writes. Each hit names the plan folder, which kind of record it
   came from, the line number, and the matching excerpt. `ARCHIVE_SEARCH: 0` means nothing
   matched; say so plainly rather than offering a near-miss.

   Why this comes first: in the SCV repo itself the words *회귀*, *훅* and *설정* appear in
   **zero** plan titles and in 25–30 plan bodies each — a title-only pick finds none of them.
   Pass several words; a single common word matches too much to rank.

2. **Fall back to the title index** when the sweep returns nothing, or when the user asks for
   a listing rather than an answer: run `bash "<plugin root>/scripts/help.sh" --archive-index`
   and read its `ARCHIVE_INDEX:` block (`<folder> | <title> | <created_at>` per entry). If it
   shows `(empty)` or `(no archive yet)`, tell the user honestly and suggest `/scv:promote`
   to create the first plan. Stop.
3. Pick the 1–5 archives the sweep ranked highest (or, in the fallback, whose `<title>` /
   `<folder>` / `<created_at>` best match). Be conservative — fewer hits beat speculative
   ones. **Read a whole PLAN.md only when the excerpt is not enough** — the excerpt plus its
   source is often the whole answer, and a plan body averages 143 lines.
4. For each archive you still need in full, read `scv/archive/<folder>/PLAN.md` (only the picked ones — don't read all). Extract: one-sentence purpose · `refs:` links · `supersedes:` if present · final outcome (look at the `Approach Overview` / `Result` sections).
5. Print a compact summary in the resolved language. Format suggestion (one block per archive):

   ```
   • <folder>  ·  <created_at>
     <title>
     <one-sentence purpose>
     refs: <jira/linear/... if any>
     supersedes: <slug if any>
   ```

6. End with a single follow-up offer: `"Want to start a new plan based on one of these? Tell me which folder and I'll open it as a conversation seed."` If the user picks one, copy the relevant excerpts into a new `scv/conversations/<timestamp>-<slug>.md` and proceed as Mode B from Step B1.

Do not enter the long Mode B conversation loop here — Mode B' answers the question and stops.
