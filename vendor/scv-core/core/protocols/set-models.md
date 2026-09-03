# SCV action: set-models

This action is owned by the wrapper adapter.

The adapter may expose the host runtime's supported execution policy, but it
must not rewrite canonical core protocols or scripts. Map the neutral
`execution_class` values in `actions.json` only when the runtime supports such
selection:

| Class | Intent |
|---|---|
| `deep` | Multi-step reasoning and implementation work. |
| `balanced` | General workflow work with moderate reasoning. |
| `economy` | Fast diagnostics and mechanical operations. |

If the runtime cannot select execution policy per action, report that
limitation and leave the current session or project policy unchanged.

SCV Core intentionally provides no executable entrypoint for this action.

The runtime default is the **session model**: a freshly installed wrapper carries no
per-command model selection, so every action runs on whatever model the user chose for
the session. A mapping (for example, cheaper models for light actions) is opt-in — the
user turns it on with this action, the choice is persisted in the shared settings file
as `SCV_MODEL_POLICY`, and the wrapper's sync re-applies it after a plugin update. A
wrapper must never ship a default that silently changes the user's model.
