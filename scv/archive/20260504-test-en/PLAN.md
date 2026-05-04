---
title: Add refund button to checkout page
slug: 20260504-test-en
author: wookiya1364
created_at: 2026-05-04
status: done
lang: english
tags: [test, internal, multilang]
raw_sources: []
refs: []
---

# Add refund button to checkout page

## Summary

Internal v0.7.3 verification PR — English language. Adds a "Refund" button on the order detail page so users can request a refund within 7 days of purchase. **This PR will be closed without merging.**

## Goals / Non-Goals

- **Goals**
  - User clicks Refund → backend processes via Stripe
  - Email confirmation after success
- **Non-Goals**
  - Partial refunds (full refund only for v1)
  - Refunds older than 7 days

## Approach Overview

User clicks Refund → `RefundController.refund(orderId, amount)` → `OrderService.getOrder` checks ownership and 7-day window → `PaymentGateway.processRefund` calls Stripe → on success, `EventBus.emit('refund.completed')` → `NotificationService` sends email.

## Steps

1. UI: Add Refund button on order detail page
2. Backend: `RefundController.refund(orderId, amount)` endpoint
3. Validation: ownership + 7-day window via `OrderService`
4. Payment: Stripe `/v1/refunds` call
5. Notification: confirmation email via SendGrid

## Related Documents

## Risks / Open Questions

- None — internal verification only.

## Links

- v0.7.3 multilang verification
