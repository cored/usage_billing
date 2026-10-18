# usage_billing

A Rails application for usage-based billing: record metered usage, close billing periods, compute invoices, sync them to Stripe, and reconcile what Stripe holds against what the ledger says it should hold.

It is event-sourced with [RailsEventStore](https://railseventstore.org). Every invoice total can be traced back, event by event, to the usage that produced it.

> **Status:** slice 0 of 6. The app boots, the event store is wired in, the store's behavior is pinned by contract specs, and the domain boundary is checked in CI. No billing logic exists yet. See [Roadmap](#roadmap).

## Why event sourcing here

Event sourcing has real costs: more concepts, eventual consistency in read models, and schema evolution for events. It is worth those costs only when the problem needs what it gives. This one needs three things at once:

1. **Idempotent ingestion.** Usage arrives over unreliable networks and will be retried. A retried event must never be counted twice. An append-only log with unique event ids makes that a property of the store rather than of application code.
2. **An audit trail of how a total was reached.** "Why is this invoice $235.19?" has to be answerable from the record, not reconstructed from current state.
3. **Reconciliation against an external system.** Comparing the ledger with Stripe needs an authoritative record of what the ledger believed and when.

Without all three, a few tables and a state machine would be the better design. [ADR-0001](docs/adr/0001-event-sourcing.md) records this reasoning.

## How it works

Usage flows left to right through six slices. Each slice is one pull request with its own specs.

| Slice | Namespace | Commands | Events | What it settles |
|---|---|---|---|---|
| 1. Usage reporting | Metering | `ReportUsage` | `PeriodOpened`, `UsageReported` | A retried request is never counted twice |
| 2. Period close | Metering | `ClosePeriod` | `PeriodClosed`, `LateUsageReported`, `LateUsageRejected` | The quantity an invoice is computed from is frozen |
| 3. Invoice generation | Invoicing | `EstablishBillableUsage`, `GenerateInvoice` | `BillableUsageEstablished`, `InvoiceGenerated` | The money math and its rounding |
| 4. Stripe sync | Invoicing | `SyncInvoiceToStripe` | `StripeDraftInvoiceCreated`, `InvoiceSyncedToStripe`, `InvoiceSyncFailed`, `InvoiceSyncRejected` | Stripe receives each invoice exactly once |
| 5. Reconciliation | Reconciliation | `ReconcileWithStripe`, `ResolveDrift` | `InvoiceReconciled`, seven drift events, `DriftResolved` | Any difference from Stripe is detected, to the cent |
| 6. Late usage | Invoicing | `AddLateBillableUsage`, `GenerateAdjustmentInvoice` | `LateBillableUsageAdded`, `PeriodAdjusted` | Usage that arrives after close is still billed correctly |

Each namespace appends only to its own streams and learns the others' facts by reacting to their events, through jobs named after the event they handle, such as `Billing::Invoicing::OnPeriodClosedJob`.

The full event model, including read models and failure cases, is in [docs/event-model.md](docs/event-model.md).

### Pricing used in examples and specs

Usage is counted as `api_requests`, billed per customer per calendar month (UTC) with graduated tiers:

| Requests in the month | Rate |
|---|---|
| 1 – 100,000 | $2.00 per 1,000 |
| 100,001 and up | $1.50 per 1,000 |

This is a placeholder. It was chosen because sub-cent unit prices force an explicit rounding rule, which real usage billing always needs.

## Design decisions

Each decision is recorded as a short ADR with its context, the alternatives considered, and its consequences.

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-event-sourcing.md) | Event sourcing with RailsEventStore; SQLite by default, swappable |
| [0002](docs/adr/0002-usage-idempotency.md) | Usage idempotency key is a UUIDv5 of customer and client key, used as the event id |
| [0003](docs/adr/0003-money-and-rounding.md) | Integer cents, round per line half away from zero, send Stripe cents per line |
| [0004](docs/adr/0004-billing-periods.md) | Periods open on first usage; grace window and plan pinned on open |
| [0005](docs/adr/0005-late-usage.md) | Late usage is billed by recompute-and-diff on the next invoice |
| [0006](docs/adr/0006-max-lateness.md) | Usage more than 30 days late is rejected |
| [0007](docs/adr/0007-adjustments-without-next-invoice.md) | Churned customers get an adjustment-only invoice; no adjustment is suppressed |
| [0008](docs/adr/0008-drift.md) | Drift is defined per invoice, on the pre-tax subtotal, with zero tolerance; one event per kind of drift |
| [0009](docs/adr/0009-domain-in-app-billing.md) | A plain Rails app, with the domain in `app/billing` under the `Billing` namespace, boundary checked by specs |
| [0010](docs/adr/0010-namespaces-reactions-and-naming.md) | Namespaces own their streams; reactions are `On<Event>` jobs; commands fold state into immutable values; naming rules |

## Known limitations

- **One writer per period stream.** Every usage event for a customer's month is appended to one stream with an expected-version check. This makes the period close trivially correct but serializes ingestion per customer. At high volume, usage would go to an append-only intake stream and the close would be a cut at a global position. See [ADR-0004](docs/adr/0004-billing-periods.md).
- **SQLite allows one writer at a time.** Concurrency specs prove the locking logic, not behavior under real contention. Run the suite against Postgres to test that. See [ADR-0001](docs/adr/0001-event-sourcing.md).
- **Out of scope:** tax, discounts, credits, payment collection, and multiple currencies.

## Project layout

```
app/billing/                 The domain, under the Billing namespace. Plain Ruby plus ruby_event_store.
  metering/                  Usage reporting and billing periods
  invoicing/                 Pricing, invoices, adjustments, Stripe sync
  reconciliation/            Comparing invoices with Stripe, drift
app/jobs/billing/<namespace>/   Asynchronous reactions: on_<event>_job.rb
app/models/                  Read models (ActiveRecord), named for their row, e.g. ReportedDrift
spec/billing/<namespace>/    Domain specs. Run without Rails, against an in-memory event store.
spec/integration/            Specs against the real event store and database
docs/                        Event model and architecture decision records
```

Inside `app/billing`, commands are the entry points. Each one loads its stream, folds the events into an immutable state value, applies rules held in value objects, and appends new events. There are no aggregate objects; one will be introduced only when a command's state becomes hard to follow without it ([ADR-0010](docs/adr/0010-namespaces-reactions-and-naming.md)).

Code in `app/billing` never references Rails, ActiveRecord, jobs or models. This is checked, not just agreed: `spec/billing` runs in its own process with Rails not loaded, so any such reference raises `NameError` ([ADR-0009](docs/adr/0009-domain-in-app-billing.md)).

## Getting started

Requirements: Ruby 3.4 or newer.

```bash
bin/setup                                                     # installs gems and prepares the SQLite database
bundle exec rspec spec/billing                                # domain specs, without Rails
bundle exec rspec                                             # full suite, with Rails
```

The full suite runs the domain specs again with Rails loaded. The boundary spec skips itself there, and verifying doubles are checked against the real models. CI runs both.

To browse streams and events, start the server with `bin/rails server` and open <http://localhost:3000/res>.

### Switching to Postgres

1. Replace `sqlite3` with `pg` in the Gemfile and update `config/database.yml`.
2. Generate the event store migration with `--data-type=jsonb`.
3. Use `RailsEventStore::JSONClient` in `config/initializers/rails_event_store.rb`.

Nothing in `app/billing` changes.

## Roadmap

- [x] **Slice 0: Setup.** Rails app, `Billing` namespace, event store wiring, store contract specs, domain boundary check, CI, ADRs.
- [ ] **Slice 1: Usage reporting.**
- [ ] **Slice 2: Period close.**
- [ ] **Slice 3: Invoice generation.**
- [ ] **Slice 4: Stripe sync.**
- [ ] **Slice 5: Reconciliation.**
- [ ] **Slice 6: Late usage and adjustments.**

Each slice adds its own section to this README when it ships.

## License

MIT
