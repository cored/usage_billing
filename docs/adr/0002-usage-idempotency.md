# 0002. Usage idempotency key

Status: Accepted

## Context

Usage producers retry on timeouts. A retried request must not be counted twice. A retried request with different content is a producer bug and must not be silently accepted.

## Decision

Every `ReportUsage` command carries an `idempotency_key` chosen by the producer. The event id is derived from it:

```
event_id = UUIDv5(namespace, "#{customer_id}:#{idempotency_key}")
```

The event store's unique index on event ids rejects the second append. On rejection, the system loads the original event and compares a SHA-256 of the canonical payload:

- Same payload: return the original event as a success.
- Different payload: reject with `IdempotencyConflict` (HTTP 409).

Keys are scoped per customer; two customers may use the same key. The resulting event is `Billing::Metering::UsageReported`, or `LateUsageReported` for a closed period. Both use this event id rule.

## Alternatives considered

- **A separate deduplication table.** A second source of truth that can disagree with the log.
- **Treating every duplicate id as success.** Hides producer bugs that change quantities between retries.
- **Random event ids with deduplication on content.** Two genuine, identical usage reports would be merged.

## Consequences

- Correctness depends on the store rejecting duplicate event ids across streams. This is pinned by a contract spec.
- Producers must generate stable keys per logical usage report.
