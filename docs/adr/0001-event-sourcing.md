# 0001. Event sourcing with RailsEventStore, SQLite by default

Status: Accepted

## Context

The system must count retried usage exactly once, explain how any invoice total was reached, and compare its records with Stripe's. Event sourcing adds cost: more concepts, eventually consistent read models, and versioning of event schemas.

## Decision

Use an event-sourced design on RailsEventStore. Commands append events to streams; read models are projections and are never used to compute money.

The application runs on SQLite. The store is configured in `config/initializers/rails_event_store.rb` and passed into domain code in `app/billing`, which never chooses a database or serializer (ADR-0009).

## Alternatives considered

- **Tables plus a state machine.** Simpler, and the right choice if any of the three needs above were absent. It loses the audit trail and puts idempotency in application code.
- **Postgres.** More production-like, but it adds a service to CI and to local setup for a repository whose purpose is to show the approach.

## Consequences

- Every behavior the design relies on from the store (unique event ids, expected-version checks) is pinned by `spec/integration/event_store_contract_spec.rb`. A database swap is valid only if those specs pass.
- SQLite allows one writer at a time. Concurrency specs verify the locking logic but not behavior under real contention.
- Switching to Postgres means the `pg` gem, a `jsonb` event store migration and `RailsEventStore::JSONClient`. Nothing in `app/billing` changes.
