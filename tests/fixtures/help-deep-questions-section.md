## Deep questions go to a background investigator (switch, v0.46.0+)

Skip this section unless `scv/scv_settings.json` sets `SCV_DELEGATE_EFFORT=on`. When on,
the per-turn hook's `[SCV delegate]` block carries the full rule, and it holds the same way
when help is invoked directly: answer now at the session's effort (SCV never changes that dial)
and hand only a *deep* question — several files to read, or a claim to verify — to the
`scv-investigator` agent in the background and say a deeper result
will follow. Its report
lands in `scv/raw/<YYYYMMDD>-research-<slug>.md`; when its summary arrives, append the
path and one line to the session's conversation file. Shallow questions are never delegated.
