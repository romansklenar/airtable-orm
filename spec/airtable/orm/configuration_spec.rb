# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Configuration, :airtable do
  describe "#table_fields" do
    it "returns all fields for a table as a hash" do
      fields = Airtable::ORM.config.table_fields(:client)
      expect(fields).to be_a(Hash)
      expect(fields).to have_key(:email)
      expect(fields).to have_key(:first_name)
      expect(fields).to have_key(:last_name)
    end
  end

  describe "#table_id" do
    it "returns table ID for a given table name" do
      table_id = Airtable::ORM.config.table_id(:client)
      expect(table_id).to be_a(String)
      expect(table_id).to start_with("tbl")
    end
  end

  describe Airtable::ORM::Configuration::MemoryCache do
    subject(:cache) { described_class.new }

    it "computes on miss and serves the cached value on hit" do
      calls = 0
      2.times { cache.fetch("key") { calls += 1 } }
      expect(calls).to eq(1)
    end

    it "caches falsey values (hit/miss decided by key presence)" do
      calls = 0
      2.times do
        cache.fetch("key") do
          calls += 1
          false
        end
      end
      expect(calls).to eq(1)
    end

    it "recomputes once :expires_in has passed" do
      calls = 0
      cache.fetch("key", expires_in: 60) { calls += 1 }
      travel(61.seconds) { cache.fetch("key", expires_in: 60) { calls += 1 } }
      expect(calls).to eq(2)
    end

    it "evicts on delete" do
      calls = 0
      cache.fetch("key") { calls += 1 }
      cache.delete("key")
      cache.fetch("key") { calls += 1 }
      expect(calls).to eq(2)
    end
  end
end
