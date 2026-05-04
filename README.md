# SCV PR Attachments

This branch is auto-managed by the SCV plugin. PR media (videos, screenshots)
are stored here, embedded into PR bodies via raw URLs.

After PR merge + N days (configurable in `.env` `SCV_ATTACHMENTS_RETENTION_DAYS`,
default 3), each slug folder is deleted automatically.

All SCV-managed state lives under the `scv/` subdirectory (`scv/manifest.json`
+ `scv/<slug>/...`). Root stays clean except for this README.

**Do not commit to this branch manually** — `scripts/pr-helper.sh` handles it.
