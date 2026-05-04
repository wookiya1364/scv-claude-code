---
title: Test FEATURE_ARCHITECTURE.md mermaid rendering on GitHub
slug: 20260504-test-mermaid-render
created_at: 2026-05-04
status: planned
---

# Architecture — Test FEATURE_ARCHITECTURE.md mermaid rendering

> Internal verification — two diagrams test pr-helper.sh inline + GitHub renderer.

## 1. Component data flow

How the test components interact.

```mermaid
flowchart LR
  User[User] -->|"clickRefund(orderId, amount)"| ReactUI[Checkout UI]
  ReactUI -->|"POST /api/refund"| RefundController
  RefundController -->|"getOrder(orderId)"| OrderService
  OrderService -->|"SELECT * FROM orders"| OrdersDB[(orders DB)]
  RefundController -->|"processRefund(paymentId, amount)"| PaymentGateway
  PaymentGateway -->|"POST /v1/refunds"| StripeAPI[(Stripe API)]
```

## 2. Position in whole architecture

Where the new RefundService sits in the system. New components highlighted in yellow.

> Source: scv/ARCHITECTURE.md (illustrative for v0.7.2 verification only)

```mermaid
flowchart TB
  subgraph "Client Layer"
    Web[Web App]
  end
  subgraph "API Layer"
    Gateway[API Gateway]
  end
  subgraph "Service Layer"
    Auth[Auth Service]
    Order[Order Service]
    Payment[Payment Service]
    Refund[Refund Service]:::new
  end
  subgraph "Data Layer"
    OrdersDB[(orders DB)]
    PaymentsDB[(payments DB)]
  end
  Web --> Gateway
  Gateway --> Auth
  Gateway --> Order
  Gateway --> Payment
  Gateway -.-> Refund
  Order --> OrdersDB
  Payment --> PaymentsDB
  Refund -.-> Payment
  classDef new fill:#FFE082,stroke:#F57C00,stroke-width:2px
```
