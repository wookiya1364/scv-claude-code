---
title: Real .webm — inline player verification
slug: 20260429-test-video-flow-v3
author: wookiya1364
created_at: 2026-04-29
status: done
kind: feature
---

## Summary
진짜 valid .webm (3초, 파란 화면 + 440Hz sine 톤) 으로 GitHub blob viewer
의 inline video player 가 작동하는지 최종 검증.

## Goals / Non-Goals
- Goals: GitHub viewer 페이지에서 비디오 inline 재생 (음성까지)
- Non-Goals: feature

## Steps
1. ffmpeg 으로 실제 webm 생성 (이미 됨)
2. pr-helper 실행
3. PR 의 video 링크 클릭 → viewer 페이지에서 player + sound 확인
