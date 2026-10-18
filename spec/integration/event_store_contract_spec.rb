require "rails_helper"

# These specs pin the behaviors of the real event store that the design depends
# on. They contain no billing logic. If one fails after an upgrade or a database
# swap, the ADR named in the example is no longer true and must be revisited
# before any slice is changed.
RSpec.describe "Event store contract" do
  module ContractProbe
    class Probed < RubyEventStore::Event; end
  end

  let(:store) { Rails.configuration.event_store }
  let(:stream) { "ContractProbe$#{SecureRandom.uuid}" }

  it "round-trips an event with its id, type and data" do
    event = ContractProbe::Probed.new(data: { quantity: 3 })
    store.publish(event, stream_name: stream)

    read = store.read.stream(stream).last
    expect(read.event_id).to eq(event.event_id)
    expect(read.event_type).to eq("ContractProbe::Probed")
    expect(read.data.deep_stringify_keys).to eq("quantity" => 3)
  end

  # ADR-0002 and ADR-0010: usage idempotency and redelivered reactions rely on
  # the store refusing a second event with the same event_id, across streams.
  it "rejects a second event with the same event_id, across streams" do
    event_id = SecureRandom.uuid
    store.publish(ContractProbe::Probed.new(event_id: event_id), stream_name: stream)

    expect {
      store.publish(ContractProbe::Probed.new(event_id: event_id), stream_name: "#{stream}-other")
    }.to raise_error(RubyEventStore::EventDuplicatedInStream)
  end

  # ADR-0004: closing a period and creating an invoice rely on optimistic concurrency.
  it "rejects an append when the expected version does not match" do
    store.publish(ContractProbe::Probed.new, stream_name: stream, expected_version: :none)

    expect {
      store.publish(ContractProbe::Probed.new, stream_name: stream, expected_version: :none)
    }.to raise_error(RubyEventStore::WrongExpectedEventVersion)
  end
end
