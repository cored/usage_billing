# 0004. Billing periods

Status: Accepted

## Context

An invoice must be computed from a quantity that cannot change underneath it. Usage keeps arriving around period boundaries.

## Decision

- A period is one customer's calendar month in UTC, as a half-open interval `[starts_at, ends_at)`. Metering owns it, in the stream `Metering::Period$<customer_id>$<yyyy-mm>`.
- A period opens on the customer's first usage: `PeriodOpened` is appended together with the first `UsageReported`.
- `PeriodOpened` pins `plan_version`, `grace_seconds` and `max_lateness_seconds`. Changing configuration affects new periods only.
- A scheduler issues `ClosePeriod` at `ends_at + grace_seconds`. The default grace is 3600 seconds, configurable.
- `ClosePeriod` reads the stream at version N and appends `PeriodClosed` with `expected_version: N`. A usage event appended in between makes the close fail and retry, so the closed total always matches the stream.
- `PeriodClosed` carries everything invoicing needs, so invoicing never reads metering's stream: `final_quantity`, `plan_version`, `starts_at`, `ends_at`.

## Alternatives considered

- **Opening periods on a schedule for every customer.** Needed for minimum fees or zero-usage invoices, neither of which is in scope.
- **Recording usage in its own intake stream and closing at a global position.** Scales better; see consequences.

## Consequences

- Customers with no usage in a month get no period and no invoice.
- All usage for a customer's month goes through one stream with an expected-version check, which serializes ingestion per customer. Acceptable at this scope. At high volume, the intake-stream design above replaces it.
