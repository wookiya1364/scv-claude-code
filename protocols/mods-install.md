# SCV action: mods-install

This action is owned by the wrapper adapter. It installs one SCV mod; the
rules shared by all mods actions are in `protocols/mods.md`.

It takes no argument. The adapter lists the mods the marketplace offers that
are not installed yet and lets the user pick one with the host's choice tool
(recommended option first). Picking is the confirmation — then it installs,
adding the mods marketplace first when it is missing. Nothing to install:
say so in one line.

SCV Core intentionally provides no executable entrypoint for this action.
