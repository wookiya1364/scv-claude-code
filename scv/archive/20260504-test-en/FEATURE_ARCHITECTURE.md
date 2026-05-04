---
title: Add refund button to checkout page
slug: 20260504-test-en
created_at: 2026-05-04
status: planned
lang: english
---

# Architecture — Add refund button to checkout page

> Two-diagram view of this feature.

## 1. Component data flow

How this feature's components interact.

```mermaid
flowchart LR
  User[User] -->|"clickRefund(orderId)"| ReactUI[Checkout UI]
  ReactUI -->|"POST /api/refund"| RefundController
  RefundController -->|"getOrder(orderId)"| OrderService
  OrderService -->|"SELECT * FROM orders"| OrdersDB[(orders DB)]
  RefundController -->|"processRefund(paymentId, amount)"| PaymentGateway
  PaymentGateway -->|"POST /v1/refunds"| StripeAPI[(Stripe API)]
  RefundController -->|"emit('refund.completed')"| EventBus
  EventBus -->|"sendEmail"| NotificationService
  NotificationService -->|"POST /v3/mail/send"| SendGrid[(SendGrid)]
```

## 2. Position in whole architecture

> Source: scv/ARCHITECTURE.md (illustrative for v0.7.3 verification)

```mermaid
flowchart TB
  subgraph "Service Layer"
    Order[Order Service]
    Payment[Payment Service]
    Refund[Refund Service]:::new
    Notification[Notification Service]
  end
  subgraph "Data Layer"
    OrdersDB[(orders DB)]
  end
  Order --> OrdersDB
  Refund -.-> Payment
  Refund -.-> Notification
  classDef new fill:#FFE082,stroke:#F57C00,stroke-width:2px
```
