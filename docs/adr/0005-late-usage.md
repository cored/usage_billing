# 0005. Late usage is billed by recompute-and-diff

Status: Accepted

## Context

Usage can arrive after its period has closed. Dropping it loses revenue and makes the record incomplete. Tiers are cumulative per period, so late requests cannot be priced on their own.

## Decision

- **Metering records it.** `ReportUsage` for a closed period appends `LateUsageReported` to the period's stream, from slice 2 onward. What happens to it next is invoicing's decision, not metering's.
- **Invoicing keeps its own copy of billable quantities**, in its own stream `Invoicing::PeriodBilling$<customer_id>$<yyyy-mm>`:
  - `OnPeriodClosedJob` issues `EstablishBillableUsage`, which appends `BillableUsageEstablished`.
  - `OnLateUsageReportedJob` issues `AddLateBillableUsage`, which appends `LateBillableUsageAdded`.
  - Both derive their event id from the source event, `UUIDv5(source_event_id)`, so a redelivered job collides with the unique index and is ignored (ADR-0010).
- **The adjustment is recomputed, never priced alone.** Invoicing folds its own stream into state and appends `PeriodAdjusted`:

```
delta_cents = subtotal(billed_quantity + late_quantity) - subtotal(billed_quantity)
```

- `PeriodAdjusted` records `as_of_version`, the version of invoicing's own stream it was computed from, and is appended with that expected version. Late usage that arrives during the calculation forces a retry. Invoicing never locks or reads metering's stream.
- The adjustment becomes a line on the customer's next invoice.
- Late usage can be delivered before the closed total, since jobs are not ordered. That is harmless: a period's billable quantity is a sum. No adjustment is computed until the original invoice exists.

## Why not price late usage alone

October billed 123,457 requests; tier 2 was 3518.55 cents, billed as 3519. Four late requests arrive.

- Priced alone: 4 × 0.15 = 0.6 cents, rounded to 1 cent.
- Recompute and diff: tier 2 becomes 3519.15 cents, rounded to 3519, so the adjustment is 0.

Pricing alone overcharges, and the error accumulates. It also misprices late usage that crosses a tier boundary.

## Consequences

- Property spec: for any split of a period's usage into on-time and late batches, the original invoice plus all adjustments equals `subtotal(total quantity)` exactly, and no adjustment is negative.
- The billable quantity exists in both metering's and invoicing's streams. That is intended: each namespace keeps the facts it acts on.
