# The billing domain lives in app/billing. Rails treats every directory under
# app/ as a root, which would make app/billing/metering define a top-level
# Metering. Mapping the directory to the Billing namespace makes the constants
# match the folders: app/billing/metering/report_usage.rb is
# Billing::Metering::ReportUsage. See docs/adr/0009-domain-in-app-billing.md.
module Billing; end

Rails.autoloaders.main.push_dir(Rails.root.join("app/billing").to_s, namespace: Billing)
