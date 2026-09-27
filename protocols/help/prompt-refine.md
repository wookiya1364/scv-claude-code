# help — per-model prompt rewrite (v0.59.0+)

Skip on `GUIDE: none`. The stop hook checks steps 1 and 7.

1. On `GUIDE: load`, read each `GUIDE_FILE:` in full, then run the `GUIDE_MARK_CMD:` line as
   given. Relay `GUIDE_STALE:`/`GUIDE_MISSING:`.
2. Skip short turns (acks).
3. Rewrite the request as the best prompt for this model: add what its guide says to state
   (goal, finish line, scope, when to stop, what to avoid), never new requirements. Name the
   guide rules applied.
4. Fill missing elements from the conversation, the repository, or the plan; say where.
5. Ask only what you cannot find: the single most consequential gap, Socratic, with your
   recommended answer; stop. If declined, use it and say so.
6. Never ask how to implement.
7. Quote the rewrite as a `>` block after the lead; add `**Rewritten request**:` (reply
   language, e.g. `**다시 쓴 요청**:`) to the turn block; work from it. Never hide the user's
   words or change model or effort.
