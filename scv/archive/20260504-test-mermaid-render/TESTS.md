# Test Plan — Test FEATURE_ARCHITECTURE.md mermaid rendering on GitHub

## Overview

Manual visual check on the rendered PR page.

## Test scenarios

### T1. Both diagrams render as inline SVG

- **Setup**: PR opened by pr-helper.sh with FEATURE_ARCHITECTURE.md present
- **Run**: Visit PR page on github.com
- **Expected**: Two Mermaid SVG diagrams appear inline in PR description, under `## Architecture diagrams`
- **Pass criterion**: Both `flowchart LR` and `flowchart TB` render visibly; `:::new` node has yellow fill

## How to run

```bash
# Manual — visit the PR URL
```

## Pass criteria

- Both diagrams render
- Yellow highlight visible on the new component
