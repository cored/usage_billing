# Loads the billing domain for specs under spec/billing.
#
# When only spec/billing is being run, the domain is loaded with Zeitwerk and
# Rails is never loaded. Any reference from app/billing to Rails, ActiveRecord,
# jobs or models then raises NameError, which is how the domain boundary is
# enforced (docs/adr/0009-domain-in-app-billing.md). CI runs it this way.
#
# When the run includes other specs, Rails' own autoloader manages app/billing.
# A second loader for the same directory would conflict, so Rails is loaded
# instead and the boundary spec skips itself.
require "zeitwerk"
require "ruby_event_store"

module BillingLoader
  DIR = File.expand_path("../app/billing", __dir__)

  def self.domain_only_run?
    RSpec.configuration.files_to_run.all? { |path| path.include?("/spec/billing/") }
  end

  def self.loader
    @loader ||= begin
      Object.const_set(:Billing, Module.new) unless defined?(::Billing)
      Zeitwerk::Loader.new.tap do |loader|
        loader.push_dir(DIR, namespace: ::Billing)
        loader.setup
      end
    end
  end
end

if BillingLoader.domain_only_run?
  BillingLoader.loader
else
  require "rails_helper"
end
