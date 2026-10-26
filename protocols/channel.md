# SCV action: channel

This action is owned by the wrapper adapter (0.71.0+).

A channel is where the installed SCV comes from: **dev**, **stage** or **prod**.
prod is the released version — what everyone gets by default. dev and stage let a
person try the newest work without waiting for a release. One channel is installed
at a time; switching swaps it.

`channel` takes one optional argument: `dev`, `stage` or `prod`. With no argument
it only reports the current channel and changes nothing.

Each channel reads one branch of the wrapper repository:

| channel | wrapper branch | holds |
|---|---|---|
| dev | `channel/dev` | the wrapper's develop + Core's develop |
| stage | `channel/stage` | the wrapper's stage + Core's stage |
| prod | none (default branch) | the latest release |

The `channel/*` branches are built by the wrapper's channel sync from those
sources. The wrapper's develop, stage and main branches and the release chain are
not touched by it — prod stays exactly what it was.

The pure part lives in Core (`scripts/lib/channel.sh`): the branch for a channel,
the channel for a branch, the swap steps, and the channel version
(`0.70.5-dev.<commit>` — the next patch with the channel and the commit, so a swap
always installs a fresh copy and the version shows what is running).

A wrapper that offers channels follows rules 1, 4, 5 and 6 of `protocols/mods.md`
(how plugins are changed, failures, reload, project files), and also:

1. Swaps in this order: remove the marketplace, add it again with the channel's
   branch (none for prod), install the plugin. Same channel already installed:
   run nothing and say so.
2. Checks that the channel's branch exists before removing anything.
3. Puts the old channel back when a step after the removal fails.
4. Reports the channel and version before and after.

A host with no channels says so in one line and runs nothing.

SCV Core intentionally provides no executable entrypoint for this action.
