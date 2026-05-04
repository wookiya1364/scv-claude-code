---
title: 決済ページに払い戻しボタンを追加
slug: 20260504-test-ja
author: wookiya1364
created_at: 2026-05-04
status: done
lang: japanese
tags: [test, internal, multilang]
raw_sources: []
refs: []
---

# 決済ページに払い戻しボタンを追加

## 概要

v0.7.3 内部検証 PR — 日本語。注文詳細ページに「払い戻し」ボタンを追加し、ユーザーが購入から 7 日以内に払い戻しをリクエストできるようにする。**マージせずに close 予定。**

## 目標 / 非目標

- **目標**
  - ユーザーが払い戻しをクリック → バックエンドが Stripe 経由で処理
  - 成功時にメール確認
- **非目標**
  - 一部払い戻し (v1 は全額のみ)
  - 7 日超過の払い戻し

## 概要 (アプローチ)

ユーザーが払い戻しをクリック → `RefundController.refund(orderId, amount)` → `OrderService.getOrder` が所有権 + 7 日ウィンドウを確認 → `PaymentGateway.processRefund` が Stripe を呼び出し → 成功時 `EventBus.emit('refund.completed')` → `NotificationService` がメール送信。

## ステップ

1. UI: 注文詳細ページに払い戻しボタン追加
2. バックエンド: `RefundController.refund(orderId, amount)` endpoint
3. バリデーション: `OrderService` を通じた所有権 + 7 日ウィンドウ
4. 決済: Stripe `/v1/refunds` 呼び出し
5. 通知: SendGrid を通じた確認メール

## Related Documents

## リスク / 未解決の質問

- なし — 内部検証専用。

## Links

- v0.7.3 多言語検証
