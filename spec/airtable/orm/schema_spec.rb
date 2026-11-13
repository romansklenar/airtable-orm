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

  describe "model schema memo (config.schema_memo_ttl)" do
    let(:model) do
      Class.new(Airtable::ORM::Base) do
        self.table_name = :case
      end
    end
    let(:cache) { Airtable::ORM.config.cache }

    before do
      @clock = 1_000.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { @clock }
      allow(cache).to receive(:fetch).and_call_original
    end

    it "defaults to 300 seconds" do
      expect(Airtable::ORM.config.schema_memo_ttl).to eq(300)
    end

    it "does not read the shared store again before the TTL elapses" do
      model.schema
      @clock += 299
      model.schema

      expect(cache).to have_received(:fetch).once
    end

    it "re-reads the shared store, not the API, once the TTL elapses" do
      model.schema
      @clock += 301
      model.schema

      expect(cache).to have_received(:fetch).twice
      expect(@meta_requests).to eq(1)
    end

    it "picks up a changed Airtable schema after Schema.clear_cache once the TTL elapses" do
      expect(model.schema[:fields].keys).to eq(["fldX"])

      @served_schema = {
        tables: [{ id: "tblQeKH7yYesvWf5p", name: "Configured",
                   fields: [{ id: "fldX", name: "Field fldX", type: "singleLineText" },
                            { id: "fldNew", name: "Field fldNew", type: "singleSelect" }] }]
      }.to_json
      described_class.clear_cache(base_id)

      @clock += 299
      expect(model.schema[:fields].keys).to eq(["fldX"]) # still memoized in this process

      @clock += 2
      expect(model.schema[:fields].keys).to eq(%w[fldX fldNew])
      expect(@meta_requests).to eq(2)
    end

    it "reads the shared store on every access when disabled" do
      Airtable::ORM.config.schema_memo_ttl = nil
      2.times { model.schema }
      Airtable::ORM.config.schema_memo_ttl = 0
      model.schema

      expect(cache).to have_received(:fetch).exactly(3).times
      expect(@meta_requests).to eq(1)
    end

    it "clear_schema_cache drops this process's memo immediately" do
      model.schema
      model.clear_schema_cache
      model.schema

      expect(cache).to have_received(:fetch).twice
    end
  end
end
