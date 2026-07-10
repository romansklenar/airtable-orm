# frozen_string_literal: true

RSpec.describe Airtable::ORM do
  it "has a version number" do
    expect(Airtable::ORM::VERSION).not_to be_nil
  end

  it "exposes the branded error hierarchy eagerly (class-body macros need no requires)" do
    expect(Airtable::ORM::ConnectionError.ancestors).to include(Airtable::ORM::Error)
    expect(Airtable::ORM::ConnectionError).not_to be < Airtable::ORM::ApiError
  end
end
