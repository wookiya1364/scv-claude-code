# SCV action: mods-remove

This action is owned by the wrapper adapter. It removes one SCV mod; the rules
shared by all mods actions are in `protocols/mods.md`.

It takes no argument. The adapter lists the installed mods and lets the user
pick one with the host's choice tool, with "keep everything" as an option.
Picking is the confirmation — then it removes the mod and checks it is gone.
Nothing installed: say so in one line.

SCV Core intentionally provides no executable entrypoint for this action.
