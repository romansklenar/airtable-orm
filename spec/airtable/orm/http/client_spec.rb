# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Http::Client do
  let(:api_key) { "test_api_key_123" }
  let(:client) { described_class.new(api_key) }

  describe "#connection" do
    it "returns a memoized Faraday connection with rate limiter and persistent adapter" do
      conn = client.connection

      expect(conn).to be_a(Faraday::Connection)
      expect(client.connection).to be(conn)
      expect(conn.url_prefix.to_s).to eq("https://api.airtable.com/")

      middleware_classes = conn.builder.handlers.map(&:klass)
      expect(middleware_classes).to include(Airtable::ORM::Http::RateLimiter)
      expect(conn.builder.adapter.name).to include("NetHttpPersistent")
    end

    it "respects a custom configured api_url" do
      # The lib no longer reads ENV — AIRTABLE_API_URL flows in via the host initializer.
      original_url = Airtable::ORM.config.api_url
      Airtable::ORM.config.api_url = "https://custom.airtable.example.com"

      custom_client = described_class.new(api_key)
      expect(custom_client.api_uri.to_s).to eq("https://custom.airtable.example.com")
    ensure
      Airtable::ORM.config.api_url = original_url
    end
  end

  describe "#headers" do
    it "includes authorization, content type, and user agent" do
      expect(client.headers).to eq(
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "User-Agent" => "airtable-orm/#{Airtable::ORM::VERSION}"
      )
    end
  end

  describe "#escape" do
    it "URL encodes strings including special and Unicode characters" do
      expect(client.escape("hello world")).to eq("hello%20world")
      expect(client.escape("hello@world.com")).to eq("hello%40world.com")
      expect(client.escape("")).to eq("")
      expect(client.escape("hello 世界")).to eq("hello%20%E4%B8%96%E7%95%8C")
    end
  end

  describe "rate limiting integration" do
    it "applies rate limiting to requests" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [200, {}, "ok"] }

      client.instance_variable_set(:@connection, Faraday.new do |builder|
        builder.request :airtable_rate_limiter, requests_per_second: 5
        builder.adapter :test, stubs
      end)

      expect do
        6.times { client.connection.get("/test") }
      end.not_to raise_error

      stubs.verify_stubbed_calls
    end
  end
end
