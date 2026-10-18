# 0010. Namespace ownership, reactions, commands and naming

Status: Accepted

## Context

Three subdomains (ADR-0009) exchange facts through events. Without explicit rules, they drift into writing each other's streams, branching on payload fields, and naming things after infrastructure instead of the domain.

## Decision

### Ownership

- Each namespace owns a category of streams, one stream per aggregate instance (one per customer-period, one per invoice), never one stream per namespace.
- A namespace appends only to its own streams. It learns other namespaces' facts by reacting to their events.
- Events across a boundary carry everything the consumer needs. A consumer never reads another namespace's stream.
- A consumer that needs a fact for a money decision records it as an event in its own stream, not in a read model. Read models are rebuildable caches with no consistency guarantee; a namespace's own stream is authoritative and supports expected-version checks.

| Namespace | Streams |
|---|---|
| Metering | `Metering::Period$<customer_id>$<yyyy-mm>` |
| Invoicing | `Invoicing::PeriodBilling$<customer_id>$<yyyy-mm>`, `Invoicing::Invoice$<invoice_id>` |
| Reconciliation | `Reconciliation::Invoice$<invoice_id>`, `Reconciliation::OrphanStripeInvoice$<stripe_invoice_id>` |

### Commands

- A command is an entry point into the domain. Controllers, jobs, schedulers and reactions call it.
- Commands exist where a decision is made: a command must have at least one rule that can reject it. Updating a read model is not a command.
- A command receives the event store as an argument, loads its stream, folds the events into an immutable state value, applies its rules, and appends new events.
- Rules live in immutable value objects (`Data.define`), such as `Money`, `PricingPlan` and the period's interval. State rebuilt from a stream is also an immutable value.
- There are no aggregate objects. An aggregate is introduced only when a command's state handling becomes hard to follow without one.

### Reactions

- One reaction class per event per namespace, named `On<Event>`. It does everything that namespace does in response: issue commands, update read models, or both.
- Asynchronous reactions are jobs: `app/jobs/billing/<namespace>/on_<event>_job.rb`, for example `Billing::Invoicing::OnPeriodClosedJob`. Each has its own queue and retry policy. A job is infrastructure, so it calls commands and read models directly; there is no domain class in between.
- Synchronous reactions live in the domain: `app/billing/<namespace>/on_<event>.rb`, with no `Job` suffix. They receive their read models by injection, with the model as the default, for example `def initialize(reported_drifts: ReportedDrift)`. The signature shows which model is used, and specs inject a double so Rails is never loaded. These reactions are the anti-corruption layer between domain and infrastructure.
- Jobs contain no business rules. A job turns an event into command calls and read-model writes. A conditional in a job means a rule belongs in a command or an event type is missing.
- Reactions across namespaces are asynchronous, so delivery is at least once and unordered. Events a reaction produces take their id from the source event, `UUIDv5(source_event_id)`, so redelivery collides with the unique index and is ignored.

### Read models

- Read models are ActiveRecord models, which makes them infrastructure. They follow Rails convention: the class is named for one row, and qualified when the bare noun would collide with domain vocabulary (`ReportedDrift`, not `Drift` or `DriftReport`).
- Injected read models are named as the collection they hold (`reported_drifts:`). This is the repository pattern without the word.
- Domain code calls domain-named class methods and scopes defined on the model (`ReportedDrift.record(...)`, `ReportedDrift.open_for(invoice_id)`), never ActiveRecord's own API (`create`, `where`, `upsert`). The model owns those methods, so doubles in specs are simple.
- Every write is keyed by the source event id, with a unique index, as an upsert. Totals are recomputed, never incremented. This keeps read models correct when a job retries.
- Domain specs use verifying doubles (`class_double`). They verify only when Rails is loaded, so CI also runs the full suite with Rails, where every double is checked against the real model. Static typing (for example Sorbet) is deferred until interface drift is an actual problem.

### Naming

- Events are `<Subject><PastTenseVerb>`, stating a domain fact: `UsageReported`, `PeriodClosed`.
- No `Event` suffix. No verb that is true of every event (Recorded, Received, Saved, Processed) unless it is itself the business fact.
- The namespace is not repeated in the name: `Billing::Metering::PeriodClosed`, not `BillingPeriodClosed`.
- A value that a consumer branches on, or that determines the payload's shape, is an event type, not a field. `BillableUsageEstablished` and `LateBillableUsageAdded` are separate events, not one event with a `source` field.
- Commands are the imperative of their main event: `ReportUsage` → `UsageReported`.

## Consequences

- A fact can exist in two namespaces' streams. That duplication is intended.
- Retries re-run a whole reaction, so both its command calls and its read-model writes must tolerate repetition. The rules above make them do so.
- More event types and more job files than a field-based design, in exchange for routing that is visible in the subscriptions and payloads with no conditional fields.
- A synchronous reaction names a model in its default argument. Ruby evaluates defaults at call time, so the boundary check (ADR-0009) does not see that reference. The check guarantees that `app/billing` loads without Rails, not that it never names a model.
