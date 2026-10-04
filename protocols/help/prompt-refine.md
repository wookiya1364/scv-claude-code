# help — per-model prompt rewrite (v0.59.0+)

Every message, however short (v0.62.0+). Hooks enforce steps 1, 4 and 5.

1. On `GUIDE: load`, read each `GUIDE_FILE:` in full, then run the `GUIDE_MARK_CMD:` line.
   Relay `GUIDE_STALE:`/`GUIDE_MISSING:`.
2. Rewrite the request as the best prompt for this model: compare it 1:1 with its checklist
   (item: msg, ctx, na or asked). Name the guide rules applied; add no requirements — except
   the SCV principle `register` prints (`contracts/rewrite-principle.md`): answer by it.
3. Fill items from the conversation, the repository, or the plan; name it. Ask only the
   single most consequential gap, Socratic, with your recommended answer.
   Never ask how to implement.
4. Register it (`model-prompting.sh register`) before any write; a turn that changes no
   file starts its `scope` with `변경 없음 —`. After a choice-tool answer, register again
   before the next write (`register --keep` when the scope is unchanged).
5. Show it twice: a top line `이렇게 이해하고 일함: …` (Understood as: …), and the rewrite
   (its REWRITE line, principle tag included) as a `>` block right after the conclusion,
   with its ctx/asked items; add `**Rewritten request**:` (e.g. `**다시 쓴 요청**:`)
   to the turn block; work from it. Never hide the user's words or change model or effort.
