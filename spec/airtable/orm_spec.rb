# frozen_string_literal: true

RSpec.describe Airtable::ORM do
  it "has a version number" do
    expect(Airtable::ORM::VERSION).not_to be_nil
  end

  it "exposes the branded error hierarchy eagerly (class-body macros need no requires)" do
    expect(Airtable::ORM::ConnectionError.ancestors).to include(Airtable::ORM::Error)
  end

  it "keeps ConnectionError a sibling of ApiError, not a subclass (persistence swallows ApiError)" do
    expect(Airtable::ORM::ConnectionError).not_to be < Airtable::ORM::ApiError
  end

  describe ".configure" do
    it "resets the memoized HTTP client so reconfiguration takes effect" do
      client_before = Airtable::ORM::Http::Client.default

      described_class.configure { |c| c.api_key = "rotated_key" }

      client_after = Airtable::ORM::Http::Client.default
      expect(client_after).not_to be(client_before)
      expect(client_after.api_key).to eq("rotated_key")
    end
  end
end
