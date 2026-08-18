# SCV action: update

This action is owned by the wrapper adapter.

The adapter must:

1. Inspect the installed wrapper version without changing project files.
2. Use only the host runtime's supported marketplace or package mechanism.
3. Pin and verify an SCV Core release before activation.
4. Explain whether a reload or a new session is required.
5. Never run project-template synchronization from inside this action.
   Plugin payloads are cached per version, so at update time the running
   session still holds the OLD payload's sync — calling it here would lay
   down the old template and report success. Tell the user instead that after
   the reload, the first Core-scripted action they run (help and status are
   the natural first) closes the gap automatically: such actions compare the
   project's stamped template version with the payload's on start and refresh
   the workflow docs when they differ. The `sync`
   action remains the by-hand re-run, and the interactive path for pre-2.x
   legacy projects, which the automatic refresh deliberately skips.

SCV Core intentionally provides no executable entrypoint for this action.
