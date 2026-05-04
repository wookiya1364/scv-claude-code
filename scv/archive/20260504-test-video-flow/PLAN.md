---
title: Test video + architecture inline rendering on GitHub PR
slug: 20260504-test-video-flow
author: wookiya1364
created_at: 2026-05-04
status: done
tags: [test, internal, video, mermaid]
raw_sources: []
refs: []
---

# Test video + architecture inline rendering on GitHub PR

## Summary

Internal verification PR for v0.7.2 video attachment + FEATURE_ARCHITECTURE.md inline. Confirms (1) Mermaid blocks render, (2) ffmpeg converts .webm → .gif, (3) orphan branch push + PR body GIF inline + .webm link. **This PR will be closed without merging** after rendering check.

## Goals / Non-Goals

- **Goals**
  - Verify video attachment flow end-to-end on GitHub PR
  - Verify FEATURE_ARCHITECTURE.md mermaid blocks render alongside videos
- **Non-Goals**
  - Not a real feature

## Approach Overview

User clicks Refund button → RefundController processes → Stripe API → confirmation email.

## Steps

1. Open dummy PR with both .webm video and FEATURE_ARCHITECTURE.md
2. Verify both render in PR body
3. Close PR + cleanup

## Related Documents

## Risks / Open Questions

- None — internal only.

## Links

- v0.7.2 verification dummy PR
