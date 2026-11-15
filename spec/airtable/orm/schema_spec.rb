# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Schema do
  let(:base_id) { Airtable::ORM.config.base_id }
  let(:raw_schema) do
    {
      tables: [
        { id: "tblQeKH7yYesvWf5p", name: "Configured",
          fields: [{ id: "fldX", name: "Field fldX", type: "singleLineText" }] },
        { id: "tblNotYetConfigured", name: "Added later",
          fields: [{ id: "fldY", name: "Field fldY", type: "singleLineText" }] }
      ]
    }.to_json
  end

  before do
    @meta_requests = 0
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get("/v0/meta/bases/#{base_id}/tables") do
      @meta_requests += 1
      [200, { "Content-Type" => "application/json" }, @served_schema || raw_schema]
    end

    connection = Faraday.new do |builder|
      builder.request :json
      builder.response :json
      builder.adapter :test, stubs
    end

    client = Airtable::ORM::Http::Client.new("test_api_key")
    allow(client).to receive(:connection).and_return(connection)
    allow(Airtable::ORM::Http::Client).to receive(:default).and_return(client)
  end

  describe ".fetch" do
    it "caches the full base schema so a table configured after the cache is warm still resolves" do
      described_class.fetch(base_id) # warm the cache under the current config (no tblNotYetConfigured)

      expect(described_class.fetch(base_id)["tblNotYetConfigured"]).to include(:fields)
      expect(@meta_requests).to eq(1) # served from cache, not a refetch
    end

    it "indexes tables and fields by their IDs" do
      schema = described_class.fetch(base_id)

      expect(schema.dig("tblQeKH7yYesvWf5p", :fields, "fldX", :type)).to eq("singleLineText")
    end

    it "refetches when forced" do
      described_class.fetch(base_id)
      described_class.fetch(base_id, force_refresh: true)

      expect(@meta_requests).to eq(2)
    end
  end

  describe ".fetch cache options" do
    it "passes config.schema_cache_expiry to the store" do
      Airtable::ORM.config.schema_cache_expiry = 12.hours
      allow(Airtable::ORM.config.cache).to receive(:fetch).and_call_original

      described_class.fetch(base_id)

      expect(Airtable::ORM.config.cache).to have_received(:fetch)
        .with("airtable:schema:#{base_id}", expires_in: 12.hours)
    end

    it "defaults the store expiry to 24 hours" do
      expect(Airtable::ORM.config.schema_cache_expiry).to eq(24.hours)
    end

    it "adds race_condition_ttl only for ActiveSupport cache stores" do
      store = ActiveSupport::Cache::MemoryStore.new
      Airtable::ORM.config.cache = store
      allow(store).to receive(:fetch).and_call_original

      described_class.fetch(base_id)

      expect(store).to have_received(:fetch).with(
        "airtable:schema:#{base_id}",
        expires_in: 24.hours, race_condition_ttl: described_class::RACE_CONDITION_TTL
      )
    end
  end

  describe "per-base memo (config.schema_memo_ttl)" do
    let(:model) do
      Class.new(Airtable::ORM::Base) do
        self.table_name = :case
        attribute :status, :string
        attribute :label, :string
      end
    end
    let(:other_model) { Class.new(Airtable::ORM::Base) { self.table_name = :case } }
    let(:cache) { Airtable::ORM.config.cache }
    let(:select_schema) do
      {
        tables: [{ id: "tblQeKH7yYesvWf5p", name: "Configured",
                   fields: [{ id: "fldX", name: "Field fldX", type: "singleLineText" },
                            { id: "fldNew", name: "Field fldNew", type: "singleSelect" }] }]
      }.to_json
    end

    before do
      @clock = 1_000.0
      allow(described_class::Memo).to receive(:clock) { @clock }
      allow(cache).to receive(:fetch).and_call_original
    end

    it "defaults to 5 minutes" do
      expect(Airtable::ORM.config.schema_memo_ttl).to eq(5.minutes)
    end

    it "is shared by every model on the base" do
      model.schema
      other_model.schema

      expect(cache).to have_received(:fetch).once
    end

    it "keeps bases apart" do
      described_class.fetch(base_id)
      described_class.clear_memo("appOtherBase")
      described_class.fetch(base_id)

      expect(cache).to have_received(:fetch).once
    end

    it "re-reads the store, not the API, once the TTL elapses" do
      model.schema
      @clock += 301
      model.schema

      expect(cache).to have_received(:fetch).twice
      expect(@meta_requests).to eq(1)
    end

    it "picks up a schema cleared from the store by another process once the TTL elapses" do
      expect(model.schema[:fields].keys).to eq(["fldX"])

      @served_schema = select_schema
      cache.delete("airtable:schema:#{base_id}") # Schema.clear_cache run elsewhere

      @clock += 299
      expect(model.schema[:fields].keys).to eq(["fldX"]) # still memoized in this process

      @clock += 2
      expect(model.schema[:fields].keys).to eq(%w[fldX fldNew])
      expect(@meta_requests).to eq(2)
    end

    it "makes Schema.clear_cache visible in this process immediately" do
      expect(model.schema[:fields].keys).to eq(["fldX"])

      @served_schema = select_schema
      described_class.clear_cache(base_id)

      expect(model.schema[:fields].keys).to eq(%w[fldX fldNew])
    end

    it "serves the previous copy when the store and API fail after the TTL" do
      stale = model.schema
      @clock += 301
      allow(cache).to receive(:fetch).and_raise(Airtable::ORM::ConnectionError, "down")

      expect(model.schema).to equal(stale)
    end

    it "raises a failed forced refresh but keeps the copy for models" do
      stale = model.schema
      allow(cache).to receive(:fetch).and_raise(Airtable::ORM::ConnectionError, "down")

      expect { described_class.fetch(base_id, force_refresh: true) }
        .to raise_error(Airtable::ORM::ConnectionError)
      expect(model.schema).to equal(stale)
    end

    it "refetches from the API on force_refresh even within the TTL" do
      model.schema
      @served_schema = select_schema
      described_class.fetch(base_id, force_refresh: true)

      expect(model.schema[:fields].keys).to eq(%w[fldX fldNew])
      expect(@meta_requests).to eq(2)
    end

    it "raises ConfigurationError when the schema lacks the table" do
      allow(described_class).to receive(:fetch).and_return({})

      expect { model.schema }.to raise_error(Airtable::ORM::ConfigurationError)
    end

    it "reads the store once per field_options call even with the memo disabled" do
      Airtable::ORM.config.schema_memo_ttl = nil
      model.config_field_mapping = { status: "fldNew", label: "fldX" }
      @served_schema = select_schema

      model.field_options(:status)

      expect(cache).to have_received(:fetch).once
    end

    it "Model.clear_schema_cache drops the base's memo" do
      model.schema
      other_model.clear_schema_cache
      model.schema

      expect(cache).to have_received(:fetch).twice
    end

    it "ORM.reset! drops every memo" do
      model.schema
      Airtable::ORM.reset!
      configure_airtable_orm_from_fixture
      allow(Airtable::ORM.config.cache).to receive(:fetch).and_call_original
      model.schema

      expect(Airtable::ORM.config.cache).to have_received(:fetch).once # fresh config, memo gone
      expect(@meta_requests).to eq(2)
    end
  end
end
