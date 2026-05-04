---
title: Test video + architecture inline rendering on GitHub PR
slug: 20260504-test-video-flow
created_at: 2026-05-04
status: planned
---

# Architecture — Test video + architecture inline rendering

> Internal verification — both diagrams and video must render together.

## 1. Component data flow

```mermaid
flowchart LR
  User[User] -->|"clickRefund(orderId)"| ReactUI[Checkout UI]
  ReactUI -->|"POST /api/refund"| RefundController
  RefundController -->|"validate(orderId)"| OrderService
  OrderService -->|"SELECT * FROM orders"| OrdersDB[(orders DB)]
  RefundController -->|"processRefund(paymentId)"| PaymentGateway
  PaymentGateway -->|"POST /v1/refunds"| StripeAPI[(Stripe API)]
```

## 2. Position in whole architecture

> Source: scv/ARCHITECTURE.md (illustrative for v0.7.2 verification)

```mermaid
flowchart TB
  subgraph "Service Layer"
    Order[Order Service]
    Payment[Payment Service]
    Refund[Refund Service]:::new
  end
  subgraph "Data Layer"
    OrdersDB[(orders DB)]
  end
  Order --> OrdersDB
  Refund -.-> Payment
  classDef new fill:#FFE082,stroke:#F57C00,stroke-width:2px
```
