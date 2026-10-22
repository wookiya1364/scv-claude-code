# SCV action: mods

This action is owned by the wrapper adapter.

SCV mods are host plugins from a separate mods marketplace (for example a
desktop-app pane). `mods` takes no argument: it brings every installed mod up to
date and lists the mods — installed (with version) and available. Its two
siblings, `mods-install` and `mods-remove`, also take no argument; each lets
the user pick one mod with the host's choice tool.

A wrapper that offers mods must:

1. Change plugins only through the host's plugin command line — never by
   editing the host's plugin folders.
2. Add the mods marketplace first when it is missing.
3. Report each mod's version before and after; an unchanged version is
   "already up to date".
4. Never report a failed step as done. A private marketplace that cannot be
   read gets the sign-in steps, not a success line.
5. Say when a reload or a new session is needed — and only when something
   changed.
6. Never touch project files.

A host with no mods says so in one line and runs nothing.

SCV Core intentionally provides no executable entrypoint for this action.
