# 0003. Money representation and rounding

Status: Accepted

## Context

Tiered rates produce sub-cent amounts. Where and how rounding happens decides whether the ledger and Stripe agree to the cent.

## Decision

- Amounts are computed as exact rationals and stored as integer cents, in a single currency (USD).
- Each invoice line is rounded once, half away from zero. The subtotal is the sum of the rounded lines, never a rounded sum.
- Stripe receives each line's amount in cents, not a unit price, so Stripe never rounds.

Worked example, 123,457 requests:

| Line | Quantity | Rate per 1,000 | Exact cents | Billed cents |
|---|---|---|---|---|
| Tier 1 | 100,000 | $2.00 | 20000 | 20000 |
| Tier 2 | 23,457 | $1.50 | 3518.55 | 3519 |
| Subtotal | | | | 23519 ($235.19) |

## Why half away from zero

- Finance can reproduce any invoice in a spreadsheet, because the common spreadsheet ROUND function uses the same rule.
- Ruby's `Rational#round` and `BigDecimal` use it by default.
- Half-even removes bias when many rounded values are summed. Here rounding happens once per line on two or three lines per invoice.
- "Away from zero" rather than "toward positive infinity", so future credit lines round symmetrically.

## Consequences

- Property spec: for any quantity, every line is a non-negative integer, tier quantities sum to the total, and the subtotal equals the sum of lines.
- Ledger and Stripe subtotals are equal by construction, so any difference found in reconciliation was introduced after sync.
