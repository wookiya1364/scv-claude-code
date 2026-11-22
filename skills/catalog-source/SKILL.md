---
name: catalog-source
description: "Switch a project to no comments in code — the pure-function catalog is the source. on moves every code comment into scv/core/catalog/pure now and bans new ones; off lifts only the ban. No argument flips it. Use whenever the user wants code comments gone or allowed again — not only when they type /scv:catalog-source."
argument-hint: "[on | off]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/catalog-source.sh:*)"]
---
