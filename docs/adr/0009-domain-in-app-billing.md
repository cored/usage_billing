# 0009. A Rails application with the domain in app/billing

Status: Accepted. Supersedes an earlier plan to package the code as a Rails engine, and a later plan to put the domain in `lib/`.

## Context

The repository exists to show an approach to usage billing, so readers of every experience level should be able to follow it. Billing rules must stay separate from Rails so they can be read, tested and reasoned about on their own.

## Decision

- The project is an ordinary Rails application.
- The domain lives in `app/billing/`, split into three subdomains that follow the event model: `metering`, `invoicing` and `reconciliation`.
- `app/billing` is mapped to the `Billing` namespace in `config/initializers/billing.rb`, so constants match folders: `app/billing/metering/report_usage.rb` is `Billing::Metering::ReportUsage`. Rails supports this from 7.1.
- Code in `app/billing` may depend on the `ruby_event_store` gem and the Ruby standard library, nothing else. Infrastructure (the event store client, ActiveRecord read models, jobs, controllers) lives in the usual Rails folders and calls into `app/billing`.
- Specs mirror the code: `spec/billing/metering/` and so on, plus Rails-convention folders such as `spec/jobs/` and `spec/integration/`.
- The boundary is enforced by specs at load time. When `spec/billing` runs on its own, `spec/billing_helper.rb` loads the domain with Zeitwerk and never loads Rails, so any reference to Rails, ActiveRecord, a job or a model raises `NameError`. CI runs it that way.

## Alternatives considered

- **A mountable Rails engine.** Useful when a second application will mount the code. There is none, and the engine adds a dummy app, a gemspec and engine-specific setup that every reader must understand first.
- **`lib/billing`.** By Rails convention `lib/` holds code that is not specific to the application. The billing domain is the application's core.
- **Plain `app/billing` without the custom namespace.** Subdomains would become top-level constants (`Metering::`), and `billing/` would only group folders.
- **Packwerk.** Stronger enforcement than this project needs.

## Consequences

- Domain specs run against RubyEventStore's in-memory repository, with no database.
- When the whole suite runs in one process, Rails is loaded and the boundary spec skips itself. The boundary is checked only when `spec/billing` runs on its own, as it does in CI.
- The check covers load-time dependencies. A synchronous reaction may name a read model in a default argument, which Ruby evaluates only at call time (ADR-0010). That is an accepted, visible coupling at the anti-corruption layer.
