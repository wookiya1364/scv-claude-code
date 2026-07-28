# SCV action: update

This action is owned by the wrapper adapter.

The adapter must:

1. Inspect the installed wrapper version without changing project files.
2. Use only the host runtime's supported marketplace or package mechanism.
3. Pin and verify an SCV Core release before activation.
4. Explain whether a reload or a new session is required.
5. Keep project-template synchronization as a separate `sync` action.

SCV Core intentionally provides no executable entrypoint for this action.
