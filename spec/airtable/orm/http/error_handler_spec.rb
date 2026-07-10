# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Http::ErrorHandler do
  def connection(&stub_block)
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get("/x", &stub_block)
    Faraday.new do |builder|
      builder.request :airtable_error_handler
      builder.adapter :test, stubs
    end
  end

  # No Faraday error may leak past the client — the whole Faraday::Error family becomes an
  # Airtable-branded ConnectionError (a sibling of ApiError, NOT a subclass: the API never
  # answered), with the original error kept as #cause for Sentry.
  [Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError, Faraday::Error].each do |faraday_error|
    it "maps #{faraday_error} to Airtable::ORM::ConnectionError, preserving the cause" do
      conn = connection { raise faraday_error }

      expect { conn.get("/x") }.to raise_error(Airtable::ORM::ConnectionError) do |error|
        expect(error).to be_a(Airtable::ORM::Error)
        expect(error).not_to be_a(Airtable::ORM::ApiError)
        expect(error.cause).to be_a(faraday_error)
      end
    end
  end

  it "passes a successful response through untouched" do
    conn = connection { [200, {}, "ok"] }

    expect(conn.get("/x").body).to eq("ok")
  end

  it "leaves a non-Faraday error (e.g. the Airtable::ORM::ApiError raised from an HTTP error response) unmapped" do
    conn = connection { raise Airtable::ORM::ApiError.new("HTTP 422", status: 422) }

    expect { conn.get("/x") }.to raise_error(Airtable::ORM::ApiError) do |error|
      expect(error).not_to be_a(Airtable::ORM::ConnectionError)
    end
  end
end
