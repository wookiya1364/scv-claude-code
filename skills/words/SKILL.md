---
name: words
description: "Show or change the project's word dictionary: the words you do not want to read and the word to say instead, inflections included (scv/words/). Use whenever the user wants B said instead of A, or asks which words are replaced — not only when they type /scv:words."
argument-hint: "[list | add <word to avoid> <word to use> | remove <word to avoid> | fill]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/words.sh:*)"]
---
