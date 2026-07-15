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
      [200, { "Content-Type" => "application/json" }, raw_schema]
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
end
