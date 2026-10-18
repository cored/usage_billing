# 0006. Maximum lateness

Status: Accepted

## Context

If late usage is accepted forever, no period's revenue is ever final.

## Decision

Usage more than 30 days after the period's `ends_at` is rejected with `LateUsageRejected`. The limit is configurable and pinned on `PeriodOpened` as `max_lateness_seconds`.

## Consequences

- After `ends_at + max_lateness_seconds`, a period's billed amount cannot change. Reconciliation can stop rechecking it, and finance has a date after which the figure is final.
- Producers that buffer usage for more than 30 days lose it, and the rejection is visible in their responses and in the log.
