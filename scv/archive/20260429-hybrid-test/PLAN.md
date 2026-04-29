---
title: Hybrid GIF + video — final v0.3.0 test
slug: 20260429-hybrid-test
author: wookiya1364
created_at: 2026-04-29
status: done
kind: feature
---

## Summary
v0.3.0 hybrid: ffmpeg 자동 GIF + 비디오 링크. PR body 에 inline GIF
preview + click-to-play webm 둘 다.

## Goals / Non-Goals
- Goals: PR 페이지에서 GIF 가 inline 자동 재생, 클릭하면 비디오로 음성까지

## Steps
1. ffmpeg 으로 webm 생성 (이미)
2. pr-helper 가 GIF 자동 생성 + 둘 다 push
3. PR body 에 inline GIF + video link
