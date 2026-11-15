# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Schema::Memo do
  subject(:memo) { described_class.new("appTEST") }

  let(:old_schema) { { "tblA" => { id: "tblA", version: 1 } } }
  let(:new_schema) { { "tblA" => { id: "tblA", version: 2 } } }
  let(:down) { Airtable::ORM::ConnectionError.new("down") }

  before do
    @clock = 1_000.0
    @loads = 0
    allow(described_class).to receive(:clock) { @clock }
  end

  def load(value = old_schema)
    memo.fetch do
      @loads += 1
      value
    end
  end

  it "does not reload before the TTL elapses" do
    load
    @clock += 299
    load

    expect(@loads).to eq(1)
  end

  it "reloads once the TTL elapses" do
    load
    @clock += 301

    expect(load(new_schema)).to eq(new_schema)
    expect(@loads).to eq(2)
  end

  it "never reloads with an infinite TTL" do
    Airtable::ORM.config.schema_memo_ttl = Float::INFINITY
    load
    @clock += 10**9
    load

    expect(@loads).to eq(1)
  end

  it "reloads on every read when disabled" do
    Airtable::ORM.config.schema_memo_ttl = nil
    2.times { load }
    Airtable::ORM.config.schema_memo_ttl = 0
    load

    expect(@loads).to eq(3)
  end

  it "starts the TTL once the load has completed, not when it began" do
    memo.fetch do
      @clock += 400 # a load slower than the TTL
      old_schema
    end
    load

    expect(@loads).to eq(0) # served from the memo
  end

  describe "outage fallback" do
    it "keeps serving the previous copy when a reload fails and retries after FALLBACK_RETRY" do
      allow(Airtable::ORM.config.logger).to receive(:warn)
      load
      @clock += 301

      expect(memo.fetch { raise down }).to equal(old_schema)
      expect(Airtable::ORM.config.logger).to have_received(:warn).with(/appTEST.*serving the previous copy/)
      @clock += described_class::FALLBACK_RETRY - 1
      expect(load(new_schema)).to equal(old_schema)
      @clock += 2
      expect(load(new_schema)).to equal(new_schema)
    end

    it "raises when there is no copy to fall back on" do
      expect { memo.fetch { raise down } }.to raise_error(Airtable::ORM::ConnectionError)
    end

    it "lets other errors propagate" do
      load
      @clock += 301

      expect { memo.fetch { raise ArgumentError } }.to raise_error(ArgumentError)
    end

    it "reloads after expire! but keeps the copy for an outage" do
      load
      memo.expire!

      expect(memo.fetch { raise down }).to equal(old_schema)
    end
  end

  describe "#refresh" do
    it "reloads before the TTL elapses" do
      load

      expect(memo.refresh { new_schema }).to equal(new_schema)
      expect(load).to equal(new_schema)
    end

    it "raises on failure and keeps the previous copy as the fallback" do
      load

      expect { memo.refresh { raise down } }.to raise_error(Airtable::ORM::ConnectionError)
      expect(load).to equal(old_schema)
    end
  end
end
