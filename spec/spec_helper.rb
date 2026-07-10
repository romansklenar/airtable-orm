# frozen_string_literal: true

require "airtable/orm"
require "airtable/orm/testing"
require "active_support/testing/time_helpers"
require "yaml"

FIXTURES = File.expand_path("fixtures", __dir__)
Airtable::ORM::Testing.schema_fixture_path = File.join(FIXTURES, "airtable.schema.json")

AIRTABLE_TEST_TABLES = YAML.load_file(File.join(FIXTURES, "config.yml"), symbolize_names: true).freeze

def configure_airtable_orm_from_fixture
  Airtable::ORM.configure do |c|
    c.api_key = "test_api_key"
    c.base_id = AIRTABLE_TEST_TABLES[:base_id]
    c.tables  = AIRTABLE_TEST_TABLES[:tables]
  end
end

# Wire the config at load time too — test classes defined in a spec file's describe body read
# ORM.config while the file loads, before any hook runs (in the host app Rails boot does this).
configure_airtable_orm_from_fixture

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include Airtable::ORM::Testing::StubHelpers, :airtable
  config.include ActiveSupport::Testing::TimeHelpers

  # Fresh, fixture-wired config per example — the gem has no host initializer, so unlike an
  # app suite (where config is boot-wired) a per-example reset can't unwire anything.
  config.before do
    Airtable::ORM.reset!
    configure_airtable_orm_from_fixture
  end

  config.before(:each, :airtable) do
    stub_airtable_http_client
  end

  config.after(:each, :airtable) do
    @stubs&.verify_stubbed_calls
    Airtable::ORM::Base.descendants.each(&:clear_schema_cache)
  end
end
