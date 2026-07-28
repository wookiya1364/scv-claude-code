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
