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

  # A thread whose memo load is parked until `release << true`; the body then provides the result.
  def start_blocked_load(&body)
    entered = Queue.new
    release = Queue.new
    thread = Thread.new do
      Thread.current.report_on_exception = false
      memo.fetch do
        entered << true
        release.pop
        body.call
      end
    end
    entered.pop
    [thread, release]
  end

  # A reader queued behind the current load; it must never run its own load.
  def start_waiter
    waiter = Thread.new do
      Thread.current.report_on_exception = false
      memo.fetch { raise "must not reload concurrently" }
    end
    wait_until_blocked(waiter)
    waiter
  end

  # Blocks until the thread is parked (waiting on a lock/queue); fails instead of hanging if it dies.
  def wait_until_blocked(thread)
    Timeout.timeout(2) { sleep 0.01 until thread.status == "sleep" || !thread.alive? }
    raise "thread died early: #{thread.value.inspect}" unless thread.alive?
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

    it "drops the copy on clear!" do
      load
      memo.clear!

      expect { memo.fetch { raise down } }.to raise_error(Airtable::ORM::ConnectionError)
    end

    it "raises when expired before any load" do
      memo.expire!

      expect { memo.fetch { raise down } }.to raise_error(Airtable::ORM::ConnectionError)
    end

    it "lets other errors propagate" do
      load
      @clock += 301

      expect { memo.fetch { raise ArgumentError } }.to raise_error(ArgumentError)
    end

    it "keeps the copy when expired during an outage" do
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

  describe "concurrent readers" do
    it "serves the previous copy while another thread reloads" do
      load
      @clock += 301
      reloader, release = start_blocked_load { new_schema }

      expect(memo.fetch { raise "must not reload concurrently" }).to equal(old_schema)
      release << true
      reloader.join
      expect(load).to equal(new_schema)
    end

    it "makes a reader wait for the reload right after expire! instead of serving the old copy" do
      load
      memo.expire!
      reloader, release = start_blocked_load { new_schema }
      waiter = start_waiter

      release << true
      expect(waiter.value).to equal(new_schema)
      reloader.join
    end

    it "makes a reader without a copy wait for the reload instead of loading again" do
      reloader, release = start_blocked_load { old_schema }
      waiter = start_waiter

      release << true
      expect(waiter.value).to equal(old_schema)
      reloader.join
    end

    it "shares a failed load with readers that queued behind it instead of repeating it" do
      leader, release = start_blocked_load do
        @clock += 1 # the load takes time
        raise down
      end
      waiter = start_waiter

      release << true
      expect { leader.join }.to raise_error(Airtable::ORM::ConnectionError)
      expect { waiter.join }.to raise_error(Airtable::ORM::ConnectionError, "down")
      expect(load).to equal(old_schema) # a later read retries normally
    end
  end

  describe "concurrent writers" do
    it "does not let a refresh overwrite an expire! that landed during its load" do
      load
      memo.refresh do
        memo.expire! # Schema.clear_cache lands mid-refresh
        new_schema
      end

      expect(load(:after_clear)).to eq(:after_clear)
    end

    it "does not store a first load that expire! overtook" do
      memo.fetch do
        memo.expire! # Schema.clear_cache lands mid-load
        old_schema
      end
      load(new_schema)

      expect(load).to equal(new_schema)
      expect(@loads).to eq(1)
    end

    it "does not store a first load that clear! overtook" do
      memo.fetch do
        memo.clear! # Schema.clear_memo lands mid-load
        old_schema
      end

      expect(load(new_schema)).to equal(new_schema)
    end

    it "does not store a reload that expire! overtook" do
      load
      @clock += 301
      memo.fetch do
        memo.expire!
        old_schema
      end

      expect(load(new_schema)).to equal(new_schema)
    end
  end
end
