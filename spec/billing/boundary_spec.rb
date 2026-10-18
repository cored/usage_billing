require "billing_helper"

RSpec.describe "Billing domain boundary" do
  it "loads every file in app/billing without Rails" do
    skip "Rails is loaded in this run. Run `bundle exec rspec spec/billing` on its own to check the boundary." if defined?(Rails)

    expect { BillingLoader.loader.eager_load }.not_to raise_error
  end
end
