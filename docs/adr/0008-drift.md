# 0008. Definition of drift

Status: Accepted

## Context

Reconciliation needs an exact definition of disagreement between the ledger and Stripe. Stripe's totals can include tax, discounts and credits, which this system does not model.

## Decision

`ReconcileWithStripe` compares each synced invoice on its pre-tax subtotal, with zero-cent tolerance. Stripe objects are matched by `metadata.ledger_invoice_id` and lines by `metadata.line_id`.

Each kind of drift is its own event, because each carries a different payload (ADR-0010):

| Event | Condition | Data |
|---|---|---|
| `SubtotalDriftDetected` | Ledger subtotal differs from Stripe's `subtotal` | invoice_id, ledger_cents, stripe_cents, delta_cents |
| `LineAmountDiverged` | A line exists on both sides with different amounts | invoice_id, line_id, ledger_cents, stripe_cents |
| `LineMissingInStripe` | A ledger line has no Stripe counterpart | invoice_id, line_id, ledger_cents |
| `UnexpectedStripeLineFound` | A Stripe line has no ledger counterpart | invoice_id, stripe_line_id, stripe_cents |
| `StripeInvoiceMissing` | The ledger recorded a sync but the Stripe invoice is gone | invoice_id, stripe_invoice_id |
| `OrphanStripeInvoiceFound` | A Stripe invoice references a ledger invoice that does not exist | stripe_invoice_id, ledger_invoice_id |
| `StripeStatusDiverged` | Stripe voided the invoice or marked it uncollectible | invoice_id, stripe_status |

When nothing differs, `ReconcileWithStripe` appends `InvoiceReconciled`.

All drift events feed the `ReportedDrift` read model for a person to resolve. Resolving is a decision, so it is a command: `ResolveDrift`, which can be rejected (already resolved, or no such drift) and appends `DriftResolved`. The system never writes corrections to Stripe automatically.

## Alternatives considered

- **One `DriftDetected` event with a `kind` field.** No consumer routes on `kind` today, but the payload's shape depends on it, which leaves fields that are nullable depending on another field.

## Consequences

- Because Stripe receives cents per line (ADR-0003), any drift was introduced after sync: a manual edit, a partial failure, or a deletion.
- Automatic correction is excluded on purpose. Automated writes to money are how double charges happen.
- Seven event types feed one read model. Adding a new kind of drift means a new event type, not a new value.
