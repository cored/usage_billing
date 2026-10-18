# The event store is infrastructure. Domain code in app/billing receives it as
# an argument and never reaches for Rails.configuration itself.
#
# SQLite stores event data as serialized text, so the plain client is used.
# On Postgres, generate the migration with --data-type=jsonb and use
# RailsEventStore::JSONClient instead. Nothing in app/billing changes.
Rails.configuration.to_prepare do
  Rails.configuration.event_store = RailsEventStore::Client.new
end
