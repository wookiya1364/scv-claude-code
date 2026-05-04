---
title: Test FEATURE_ARCHITECTURE.md mermaid rendering on GitHub
slug: 20260504-test-mermaid-render
author: wookiya1364
created_at: 2026-05-04
status: done
tags: [test, internal, mermaid]
raw_sources: []
refs: []
---

# Test FEATURE_ARCHITECTURE.md mermaid rendering on GitHub

## Summary

Internal verification PR for v0.7.2 — confirms that GitHub renders Mermaid blocks inline when pr-helper.sh injects them into the PR body. **This PR will be closed without merging** after the rendering check.

## Goals / Non-Goals

- **Goals**
  - Verify that `## Architecture diagrams` section in PR body renders both diagrams as inline SVG.
  - Confirm `:::new` highlighting works on the GitHub side.
- **Non-Goals**
  - Not introducing any code change.
  - Not for merging.

## Approach Overview

Open a dummy PR with a FEATURE_ARCHITECTURE.md that has two valid Mermaid blocks. pr-helper.sh extracts and inlines them. Check the rendered PR page.

## Steps

1. Create dummy archive folder
2. Run pr-helper.sh
3. Open PR and inspect rendering
4. Close PR + clean up

## Related Documents

## Risks / Open Questions

- None — internal verification only.

## Links

- v0.7.2 release context
