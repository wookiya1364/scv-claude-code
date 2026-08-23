---
name: guard
version: 1.0.0
status: active
last_updated: 2026-08-12
standard_version: 1.0.0
merge_policy: overwrite
---

# Workspace guard contract

The guard is a `PreToolUse` hook that denies two things: creating a plan file
without a receipt, and writing outside the workflow directory without a receipt.
This file is the single declaration both the guard and
`tests/test-guard-consistency.sh` read, so a rule and the documents describing it
cannot drift apart silently.

A **receipt** is minted when the host itself reports that an SCV action is
running. The model cannot fabricate a host event, which is what makes the receipt
worth keying on — unlike any marker written into the project, which the model
could write itself.

## Guarded path classes

```guard:guarded
plan-create   <scv_root>/promote/*/PLAN.md
plan-create   <scv_root>/promote/*/TESTS.md
plan-create   <scv_root>/promote/*/FEATURE_ARCHITECTURE.md
outside-write **
```

`plan-create` matches creation only. Editing a plan file that already exists is
always allowed — filling in `<TODO>` spots and transitioning `status:` are normal
steps, and denying them would break the very actions the guard protects.

`outside-write` means any path in the project working tree that is neither under
`<scv_root>` nor in the exempt list below.

## Exempt path classes

```guard:exempt
*.md
.gitignore
.gitattributes
LICENSE
<host_config>
```

This list is duplicated by the CI provenance gate on purpose, and
`core/tests/test-guard.sh` (T21) asserts the two agree. If they diverge, the
product states two different definitions of "a code change".

`<host_config>` is the host's own settings file (for example a runtime config
under a dotted host directory). It is host configuration, not project code, and
its keys are negotiated with the user at runtime, so no fixed script can write it
generically.

The settings files are deliberately **not** exempt. A project's settings file is content
worth watching; the sanctioned writes go through `scripts/settings-set.sh`, which is a
shell invocation and therefore never reaches an editor-tool rule at all.

## Receipt-minting actions

Every action in `core/actions.json` mints. The set is declared here so adding a
sixteenth action fails CI until someone records a guard decision for it.

```guard:mint
help
status
promote
work
codegen
deck
update
regression
report
sync
install-deps
workspace
handoff
set-models
routine
```

Two of these (`update`, `set-models`) have `entrypoint: null` in
`core/actions.json` — Core ships no executable for them. On a host that mints from
a script invocation, they mint from the wrapper adapter's own scripts instead, so
an adapter script directory must be part of the mint allowlist.
`SCV_GUARD_SCRIPTS` accepts a colon-separated list of directories for exactly
this reason — the vendored Core scripts and the adapter's own scripts are two
places, and with a single value the adapter-owned actions could never mint.
Each entry keeps the fixed-string match; the list adds no globs and no regex.
Entries must be absolute paths — anything else (including whitespace fragments
from a hand-wrapped list) is dropped rather than matched, because a relative
fragment is a substring almost every command contains.

The match itself is a substring test on the command text: a command that
merely NAMES a listed directory mints, without executing anything from it.
That is a known and accepted limit — the guard closes the accidental path,
and an adapter adding a directory to the list should know it is also handing
the model a phrase that unlocks the session.

Narrowing this set was tried and rejected. With only `{work, codegen}` minting,
five protocol-instructed writes are denied while an action is legitimately
running — which is worse than a passive document sanctioning a bypass, because
the protocol is telling the model to do the denied thing.

The cost of the wide set is stated plainly: one read-only action unlocks the
session. What the guard enforces is "an SCV action ran in this session", not
"this write belongs to planned work". The second property is enforced by the CI
provenance gate at merge time. The two layers do different jobs and must not be
described as if they did the same one.

A third gate, `check-vendor-provenance.sh`, sits beside the provenance one and
answers a different question again: not what produced a change, but who moved
the pinned Core. It is not part of this contract and never denies a tool call —
it is named here only so the three are not mistaken for one.

## Self-block audit

Every protocol that writes a guarded path must run an action script before that
write, or the guard blocks the action it exists to protect. Verified by hand on
2026-08-12; a regex cannot express the ordering relation reliably.

| Protocol | First mint | Guarded write before it? |
|---|---|---|
| codegen | 47 | no |
| deck | 75 | no |
| handoff | 62 | no — its writes target a temp dir, outside the working tree |
| help | 64 (`settings-set.sh`) | no — the settings write *is* the first script call |
| install-deps | 36 | no |
| promote | 12 | no |
| regression | 45 | no |
| report | 18 | no |
| routine | 45 | no |
| status | 28 | no |
| sync | 40 | no |
| work | 32 | no |
| workspace | 36 | no |
| set-models | — | adapter-owned; Core ships no write |
| update | — | adapter-owned; Core ships no write |

`help` was the one real ordering hole: its language setting was written before
any script ran, so on a mint-from-script host the first interaction in a fresh
project had no receipt yet. Routing it through `scripts/settings-set.sh` closed it, and
the fix is self-reinforcing — the write and the mint are now the same call.

## Sanctioned exceptions

Phrases that read like a bypass but are not, anchored to the exact line so an
excuse cannot outlive the text it excuses. `tests/test-guard-consistency.sh`
fails when an anchor no longer matches.

```guard:exceptions
core/protocols/deck.md:145 — forbids hand-editing generated output; the opposite of a sanction
core/integrations/loop-runner.md:6 — the subject is the user writing their own loop prompt, not the agent authoring a plan
core/template/scv/raw/README.md:110 — forbids hand-creating a plan folder and says why
core/protocols/promote.md:43 — forbids moving raw originals by hand
core/protocols/promote.md:110 — forbids hand-editing the settings file; routes the write to a script instead
core/protocols/promote.md:864 — about mockup colour values, unrelated to workflow artefacts
```

## Failure behavior

Two inputs fail **open**, and only those two. An empty payload — nothing arrived
on stdin, so there is no write to judge. No JSON reader on the machine — with
neither `jq` nor `python3` the guard cannot see a path at all. Both print one line
to stderr and allow.

A payload that arrives but does not parse also allows, by a different route and
without the stderr line: no target path can be read out of it, so neither rule
finds anything to match.

Failing open on unreadable input is deliberate and it is not a strength trade
worth reversing. The hosts already proceed when a hook script is missing or times
out, so an adversary deletes the script rather than corrupting its logic — closing
on unreadable input buys almost nothing against that, while a single guard bug
would deny every write in every project at once. Make the failure loud, not fatal.

**An unusable receipt store fails closed — and says so.** This is the exception
to everything above. Closing is deliberate: the receipt's absence is what
denies, and a shell tool can chmod the store, so failing open here would let one
command switch the guard off. The closed posture belongs to the two write
rules — gate-bash still allows a command that calls into a listed script
directory, receipt or not, because bricking the very actions that mint would
leave no way out. What used to be wrong was the silence. `mint` was
best-effort and mute, `has_receipt` stayed false for the whole session, both
rules refused everything, and the deny message said "run an action" — which
mints into the same broken store and cannot help. Now the failure is loud at
both ends: a mint that cannot record prints one stderr line naming the store,
and a gate that denies because the store is unusable swaps its reason for one
that names the store path and points at `SCV_GUARD_STATE`, instead of blaming
the workflow.

The guard is inert where SCV is not adopted: resolve the workflow root by walking
up from the payload's working directory, and allow immediately when there is
none. Do not test for a directory relative to the current directory — a caller
one level down would silently disable the guard.
