# Test Plan — Test video + architecture inline rendering

## Overview

Verify both video and mermaid blocks render in PR body.

## Test scenarios

### T1. Video GIF inline + .webm link

- **Setup**: dummy 2-second .webm in test-results/
- **Run**: pr-helper.sh creates PR
- **Expected**: PR body has GIF auto-playing inline + .webm link
- **Pass criterion**: Visible animated GIF in PR description, clickable .webm link

### T2. Mermaid diagrams alongside video

- **Setup**: FEATURE_ARCHITECTURE.md with two mermaid blocks
- **Expected**: Both diagrams render as SVG in PR description
- **Pass criterion**: Two visible diagrams + animated GIF in same PR body

## How to run

```bash
# Manual visual check on PR page
```

## Pass criteria

- Both video and mermaid render together
