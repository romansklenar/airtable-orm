# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Http::RateLimiter do
  before do
    @stubs = Faraday::Adapter::Test::Stubs.new
    @rps = 5
    @sleeps = []
    @connection = Faraday.new do |builder|
      builder.request :airtable_rate_limiter, requests_per_second: @rps, sleeper: ->(s) { @sleeps << s }
      builder.adapter :test, @stubs
    end

    @stubs.get("/whatever") do |_env|
      [200, {}, "walrus"]
    end
  end

  # Access the rate limiter middleware instance from the Faraday stack
  def rate_limiter
    @connection.app
  end

  def tracked_requests
    rate_limiter.instance_variable_get(:@requests)
  end

  after do
    rate_limiter.clear
  end

  describe "rate limiting behavior" do
    it "passes through single request without sleeping" do
      @connection.get("/whatever")
      expect(@sleeps).to be_empty
    end

    it "sleeps on the rps plus one request" do
      @rps.times do
        @connection.get("/whatever")
      end

      expect(@sleeps).to be_empty

      @connection.get("/whatever")

      expect(@sleeps.size).to eq(1)
      expect(@sleeps.first).to be > 0.9
    end

    it "tracks requests using monotonic clock" do
      @connection.get("/whatever")
      expect(tracked_requests.size).to eq(1)
      expect(tracked_requests.first).to be_a(Numeric)
    end

    it "maintains sliding window of requests" do
      (@rps + 1).times do
        @connection.get("/whatever")
      end

      expect(tracked_requests.size).to eq(@rps)
    end

    it "does not sleep when the tracked window is older than one second" do
      @rps.times { @connection.get("/whatever") }
      aged = tracked_requests.map { |t| t - 10 }
      rate_limiter.instance_variable_set(:@requests, aged)

      @connection.get("/whatever")

      expect(@sleeps).to be_empty
    end

    it "sleeps outside the mutex so other threads' requests are not blocked" do
      connection = nil
      locked_during_sleep = nil
      sleeper = lambda do |_seconds|
        locked_during_sleep = connection.app.instance_variable_get(:@mutex).locked?
      end
      connection = Faraday.new do |builder|
        builder.request :airtable_rate_limiter, requests_per_second: 2, sleeper: sleeper
        builder.adapter :test, @stubs
      end

      3.times { connection.get("/whatever") }

      expect(locked_during_sleep).to be(false)
    end
  end

  describe "thread safety" do
    it "uses mutex for thread-safe operation" do
      limiter = described_class.new(
        ->(env) { env },
        requests_per_second: @rps
      )

      expect(limiter.instance_variable_get(:@mutex)).to be_a(Mutex)
    end
  end

  describe "initialization" do
    it "accepts custom sleeper function" do
      custom_sleeps = []
      custom_sleeper = ->(s) { custom_sleeps << s }

      connection = Faraday.new do |builder|
        builder.request :airtable_rate_limiter, requests_per_second: 2, sleeper: custom_sleeper
        builder.adapter :test, @stubs
      end

      3.times { connection.get("/whatever") }

      expect(custom_sleeps).not_to be_empty
    end

    it "starts with empty requests" do
      limiter = described_class.new(
        ->(env) { env },
        requests_per_second: @rps
      )

      expect(limiter.instance_variable_get(:@requests)).to be_empty
    end
  end
end
