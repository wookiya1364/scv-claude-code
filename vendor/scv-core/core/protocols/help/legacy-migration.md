# help — Legacy .conversations/ migration

Read from `/scv:help` at "Legacy .conversations/ migration". Follow it, then return to the protocol where you left off.

> `<plugin root>` below means the directory two levels above this file (this file lives at
> `<plugin root>/protocols/help/`; the helper scripts live at `<plugin root>/scripts/`). Branch
> files are read as plain text, so no path placeholder is expanded here — derive the absolute
> path from where you read this file.

### Legacy `.conversations/` migration (offer when detected)

If `LEGACY_CONVERSATIONS:` is not `(none)`, the project still has the old
gitignored `scv/.conversations/`. These files are invisible to the resume flow
now (it reads `scv/conversations/` only). Ask once:

```
Question: "Found legacy local conversations in scv/.conversations/ (N file(s)). Migrate them to the committed scv/conversations/?"
options:
[1] "Yes — migrate (redaction-filtered)"
    description: "Each file (including archive/) is passed through journal-append.sh --redact-only and the redacted copy is written to scv/conversations/ (same relative name); the local original is then removed. The redacted copies are committed with your next commit."
[2] "Not now — keep them local"
    description: "Nothing changes. The legacy files stay gitignored and are NOT read by the resume flow; re-run /scv:help anytime to migrate later."
```

On [1]: `mkdir -p scv/conversations` (and `scv/conversations/archive` when the
legacy `archive/` exists), then for each legacy `*.md` write the
redaction-filtered content to the corresponding `scv/conversations/` path and
delete the original. Print a one-line summary (`migrated N conversation(s)`).
On [2]: do nothing.
