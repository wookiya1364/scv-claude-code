---
title: 결제 페이지에 환불 버튼 추가
slug: 20260504-test-ko
author: wookiya1364
created_at: 2026-05-04
status: done
lang: korean
tags: [test, internal, multilang]
raw_sources: []
refs: []
---

# 결제 페이지에 환불 버튼 추가

## 요약

v0.7.3 내부 검증 PR — 한국어. 주문 상세 페이지에 "환불" 버튼을 추가해 사용자가 구매 7 일 이내에 환불을 요청할 수 있게 함. **머지하지 않고 close 예정.**

## 목표 / 비목표

- **목표**
  - 사용자가 환불 클릭 → 백엔드가 Stripe 통해 처리
  - 성공 시 이메일 확인
- **비목표**
  - 부분 환불 (v1 은 전액 환불만)
  - 7 일 초과 환불

## 개요

사용자 환불 클릭 → `RefundController.refund(orderId, amount)` → `OrderService.getOrder` 가 소유권 + 7 일 윈도우 확인 → `PaymentGateway.processRefund` 가 Stripe 호출 → 성공 시 `EventBus.emit('refund.completed')` → `NotificationService` 가 이메일 발송.

## 단계

1. UI: 주문 상세 페이지에 환불 버튼 추가
2. 백엔드: `RefundController.refund(orderId, amount)` endpoint
3. 검증: `OrderService` 통한 소유권 + 7 일 윈도우
4. 결제: Stripe `/v1/refunds` 호출
5. 알림: SendGrid 통한 확인 이메일

## Related Documents

## 위험 / 미해결 질문

- 없음 — 내부 검증 전용.

## Links

- v0.7.3 다국어 검증
