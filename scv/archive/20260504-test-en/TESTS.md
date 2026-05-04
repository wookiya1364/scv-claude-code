# Test Plan — Add refund button to checkout page

## Overview

E2E + unit tests for the refund flow.

## Test scenarios

### T1. Successful refund within 7 days

- **Setup**: order placed 3 days ago, paid via Stripe
- **Run**: click Refund button
- **Expected**: refund processed, email sent
- **Pass criterion**: HTTP 200, refund event emitted

### T2. Refund denied after 7 days

- **Setup**: order placed 10 days ago
- **Run**: click Refund button
- **Expected**: HTTP 403, error message shown
- **Pass criterion**: no refund processed

## How to run

```bash
npm run test:e2e -- refund
```

## Pass criteria

- All scenarios pass
- Coverage ≥ 80%

## Related Documents
