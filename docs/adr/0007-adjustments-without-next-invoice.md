# 0007. Adjustments when there is no next invoice

Status: Accepted

## Context

Adjustments ride on the customer's next invoice (ADR-0005), but periods open only on usage (ADR-0004). A customer who stops using the product has no next period and no next invoice to carry the adjustment.

## Decision

- The month-end scheduler issues `GenerateAdjustmentInvoice` for any customer with pending adjustments and no open period. It appends `InvoiceGenerated` like any other invoice, so sync and reconciliation need no special case.
- Every adjustment is billed, however small. There is no minimum and no suppression.

## Alternatives considered

- **Writing off adjustments below a threshold.** Breaks the guarantee that a period's invoices sum to its true total, unless the suppressed amount is carried forward, which adds state.

## Consequences

- Customers may receive small adjustment-only invoices after churning.
- The full-information invariant from ADR-0005 holds exactly.
