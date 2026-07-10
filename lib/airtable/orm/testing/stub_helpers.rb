# frozen_string_literal: true

module Airtable
  module ORM
    # Opt-in RSpec test support: `require "airtable/orm/testing"`. Depends on rspec-mocks at
    # runtime, which is why the directory is ignored by the gem's Zeitwerk loader.
    module Testing
      class << self
        # Absolute path to a JSON dump of /v0/meta/bases/:id/tables — the host points this at
        # its own fixture before using stub_airtable_schema.
        attr_accessor :schema_fixture_path
      end

      # Include into RSpec (`config.include Airtable::ORM::Testing::StubHelpers, :airtable`)
      # and call stub_airtable_http_client in a before hook — no HTTP leaves the process.
      module StubHelpers
        # Stub schema fetch to use the fixture file instead of the /v0/meta API.
        # Returns the same schema data for all fetch calls, so tests work regardless
        # of which base they're configured for.
        def stub_airtable_schema
          path = Testing.schema_fixture_path
          raise ArgumentError, "Set Airtable::ORM::Testing.schema_fixture_path first" unless path

          raw_schema = JSON.parse(File.read(path))
          indexed_schema = Airtable::ORM::Schema.send(:indexed_schema, raw_schema)

          allow(Airtable::ORM::Schema).to receive(:fetch).and_return(indexed_schema)
        end

        # Route every request through a Faraday test adapter (returned for stubbing) and
        # bypass the API-key check in Http::Client.default with a real client instance so
        # escape/other helpers keep working.
        def stub_airtable_http_client
          @stubs = Faraday::Adapter::Test::Stubs.new

          stub_connection = Faraday.new do |builder|
            builder.request :json
            builder.response :json
            builder.adapter :test, @stubs
          end

          fake_client = Airtable::ORM::Http::Client.new("test_api_key")
          allow(fake_client).to receive(:connection).and_return(stub_connection)
          allow(Airtable::ORM::Http::Client).to receive(:default).and_return(fake_client)

          stub_airtable_schema

          @stubs
        end
      end
    end
  end
end
