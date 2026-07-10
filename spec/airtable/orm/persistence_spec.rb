# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Persistence do
  # Create a test class that includes all necessary concerns
  let(:test_class) do
    Class.new do
      include ActiveModel::Model
      extend ActiveModel::Callbacks
      include Airtable::ORM::Attributes
      include Airtable::ORM::Persistence
      include Airtable::ORM::Querying

      def self.name
        "TestClient"
      end

      def self.base_id
        Airtable::ORM.config.base_id
      end

      self.table_name = :clients

      attribute :email, :string
      attribute :first_name, :string
      attribute :notes, :string
    end
  end

  let(:base_id) { "appTestBase123" }
  let(:table_id) { "tblTestTable123" }

  before do
    # Stub config - must be done before creating test_class
    allow(Airtable::ORM.config).to receive(:base_id).and_return(base_id)
    allow(Airtable::ORM.config).to receive(:table_id).with(:clients).and_return(table_id)
    allow(Airtable::ORM.config).to receive(:table_fields).with(:clients).and_return({
                                                                                      email: "fldEmail123",
                                                                                      first_name: "fldFirstName123",
                                                                                      notes: "fldNotes123"
                                                                                    })

    # Stub schema
    allow(Airtable::ORM::Schema).to receive(:fetch).and_return({
                                                                 table_id => {
                                                                   fields: {
                                                                     "fldEmail123" => { name: "Email", type: "email" },
                                                                     "fldFirstName123" => { name: "First Name",
                                                                                            type: "singleLineText" },
                                                                     "fldNotes123" => { name: "Notes",
                                                                                        type: "multilineText" }
                                                                   }
                                                                 }
                                                               })
  end

  describe ".find_many" do
    it "returns empty array for empty input" do
      expect(test_class.find_many([])).to eq([])
    end

    it "preserves the order of requested IDs" do
      # Create mock records with specific IDs
      records = [
        test_class.new(email: "first@example.com"),
        test_class.new(email: "second@example.com"),
        test_class.new(email: "third@example.com")
      ]

      records[0].send(:assign_persistence_state, id: "rec111", created_at: Time.current, persisted: true)
      records[1].send(:assign_persistence_state, id: "rec222", created_at: Time.current, persisted: true)
      records[2].send(:assign_persistence_state, id: "rec333", created_at: Time.current, persisted: true)

      # Stub where to return records in a different order than requested
      allow(test_class).to receive(:where).and_return([records[2], records[0], records[1]])

      # Request in specific order
      requested_ids = %w[rec111 rec222 rec333]
      result = test_class.find_many(requested_ids)

      # Verify returned order matches requested order
      expect(result.map(&:id)).to eq(requested_ids)
    end

    it "handles IDs returned in arbitrary order from API" do
      records = [
        test_class.new(email: "a@example.com"),
        test_class.new(email: "b@example.com"),
        test_class.new(email: "c@example.com"),
        test_class.new(email: "d@example.com"),
        test_class.new(email: "e@example.com")
      ]

      records[0].send(:assign_persistence_state, id: "recAAA", created_at: Time.current, persisted: true)
      records[1].send(:assign_persistence_state, id: "recBBB", created_at: Time.current, persisted: true)
      records[2].send(:assign_persistence_state, id: "recCCC", created_at: Time.current, persisted: true)
      records[3].send(:assign_persistence_state, id: "recDDD", created_at: Time.current, persisted: true)
      records[4].send(:assign_persistence_state, id: "recEEE", created_at: Time.current, persisted: true)

      # API returns in reverse order
      allow(test_class).to receive(:where).and_return(records.reverse)

      # Request in forward order
      requested_ids = %w[recAAA recBBB recCCC recDDD recEEE]
      result = test_class.find_many(requested_ids)

      # Verify order is preserved
      expect(result.map(&:id)).to eq(requested_ids)
    end

    it "validates record IDs to prevent formula injection" do
      expect do
        test_class.find_many(["invalid_id"])
      end.to raise_error(ArgumentError, /Invalid Airtable record ID/)
    end
  end

  describe ".update_many" do
    let(:connection) { instance_double(Faraday::Connection) }

    before do
      client = instance_double(Airtable::ORM::Http::Client, connection: connection)
      allow(client).to receive(:escape).and_return(table_id)
      allow(test_class).to receive(:client).and_return(client)
    end

    def build_persisted_record(id: "rec#{SecureRandom.hex(8)}", **attrs)
      record = test_class.new(**attrs)
      record.send(:assign_persistence_state, id: id, created_at: Time.current, persisted: true)
      record.clear_changes_information
      record
    end

    def batch_response_body(records)
      {
        "records" => records.map do |record|
          {
            "id" => record.id,
            "createdTime" => "2024-01-01T00:00:00.000Z",
            "fields" => record.changed.each_with_object({}) do |attr, hash|
              field_id = test_class.field_mapping[attr.to_sym]
              hash[field_id] = record.public_send(attr) if field_id
            end
          }
        end
      }
    end

    it "sends a single batch PATCH for valid changed records" do
      r1 = build_persisted_record(id: "rec111", email: "a@example.com")
      r2 = build_persisted_record(id: "rec222", email: "b@example.com")
      r1.email = "new_a@example.com"
      r2.email = "new_b@example.com"

      response = instance_double(Faraday::Response, success?: true, status: 200, body: batch_response_body([r1, r2]))
      expect(connection).to receive(:patch).once.and_return(response)

      result = test_class.update_many([r1, r2])
      expect(result.updated).to contain_exactly(r1, r2)
      expect(result.failed).to be_empty
    end

    it "splits into multiple batches when exceeding BATCH_SIZE" do
      records = 12.times.map do |i|
        r = build_persisted_record(id: "rec#{format("%03d", i)}", email: "old#{i}@example.com")
        r.email = "new#{i}@example.com"
        r
      end

      # Expect two PATCH calls: one with 10 records, one with 2
      call_count = 0
      allow(connection).to receive(:patch) do |_path, body|
        call_count += 1
        batch_records = body[:records]

        response_body = {
          "records" => batch_records.map do |rec|
            { "id" => rec[:id], "createdTime" => "2024-01-01T00:00:00.000Z", "fields" => rec[:fields] }
          end
        }
        instance_double(Faraday::Response, success?: true, status: 200, body: response_body)
      end

      result = test_class.update_many(records)
      expect(call_count).to eq(2)
      expect(result.updated.size).to eq(12)
      expect(result.failed).to be_empty
    end

    it "skips unchanged records without API call" do
      r1 = build_persisted_record(id: "rec111", email: "a@example.com")
      r2 = build_persisted_record(id: "rec222", email: "b@example.com")
      # Neither record has changes

      expect(connection).not_to receive(:patch)

      result = test_class.update_many([r1, r2])
      expect(result.skipped).to contain_exactly(r1, r2)
      expect(result.updated).to be_empty
      expect(result.failed).to be_empty
    end

    it "handles a mix of changed and unchanged records" do
      unchanged = build_persisted_record(id: "rec111", email: "same@example.com")
      changed = build_persisted_record(id: "rec222", email: "old@example.com")
      changed.email = "new@example.com"

      response = instance_double(Faraday::Response, success?: true, status: 200, body: batch_response_body([changed]))
      expect(connection).to receive(:patch).once.and_return(response)

      result = test_class.update_many([unchanged, changed])
      expect(result.updated).to contain_exactly(changed)
      expect(result.skipped).to contain_exactly(unchanged)
      expect(result.failed).to be_empty
    end

    it "adds all batch records to failed on API error" do
      r1 = build_persisted_record(id: "rec111", email: "a@example.com")
      r2 = build_persisted_record(id: "rec222", email: "b@example.com")
      r1.email = "new_a@example.com"
      r2.email = "new_b@example.com"

      error_body = { "error" => { "type" => "INVALID_REQUEST", "message" => "batch failed" } }
      response = instance_double(Faraday::Response, success?: false, status: 422, body: error_body)
      allow(connection).to receive(:patch).and_return(response)

      result = test_class.update_many([r1, r2])
      expect(result.updated).to be_empty
      expect(result.failed).to contain_exactly(r1, r2)
    end

    it "marks new (unpersisted) records as failed" do
      new_record = test_class.new(email: "new@example.com")

      expect(connection).not_to receive(:patch)

      result = test_class.update_many([new_record])
      expect(result.failed).to contain_exactly(new_record)
      expect(result.updated).to be_empty
    end

    it "marks invalid records as failed without API call" do
      record = build_persisted_record(id: "rec111", email: "a@example.com")
      record.email = "new@example.com"
      allow(record).to receive(:invalid?).and_return(true)

      expect(connection).not_to receive(:patch)

      result = test_class.update_many([record])
      expect(result.failed).to contain_exactly(record)
    end

    it "applies response fields back to records" do
      record = build_persisted_record(id: "rec111", email: "old@example.com")
      record.email = "submitted@example.com"

      # Airtable may transform the value
      response_body = {
        "records" => [{
          "id" => "rec111",
          "createdTime" => "2024-01-01T00:00:00.000Z",
          "fields" => { "fldEmail123" => "transformed@example.com" }
        }]
      }
      response = instance_double(Faraday::Response, success?: true, status: 200, body: response_body)
      allow(connection).to receive(:patch).and_return(response)

      test_class.update_many([record])

      expect(record.email).to eq("transformed@example.com")
      expect(record).to be_persisted
      expect(record.changed?).to be false
    end
  end

  describe "#fields_for_update" do
    it "includes fields that were changed to nil" do
      record = test_class.new(email: "test@example.com", first_name: "John", notes: "Some notes")

      # Mark as persisted to avoid triggering changed state
      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information

      # Change a field to nil
      record.first_name = nil

      # Verify the field is marked as changed
      expect(record.changed?).to be true
      expect(record.changed).to include("first_name")

      # Verify fields_for_update includes the nil value (using field ID as key)
      changed = record.fields_for_update
      expect(changed).to have_key("fldFirstName123")
      expect(changed["fldFirstName123"]).to be_nil
    end

    it "includes fields that were changed from nil to a value" do
      record = test_class.new(email: "test@example.com", first_name: nil)

      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information

      # Change from nil to a value
      record.first_name = "Jane"

      # Verify fields_for_update includes the new value (using field ID as key)
      changed = record.fields_for_update
      expect(changed).to have_key("fldFirstName123")
      expect(changed["fldFirstName123"]).to eq("Jane")
    end

    it "excludes fields that were not changed" do
      record = test_class.new(email: "test@example.com", first_name: "John", notes: "Some notes")

      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information

      # Change only one field
      record.first_name = "Jane"

      # Verify only changed field is included (using field IDs as keys)
      changed = record.fields_for_update
      expect(changed.keys).to contain_exactly("fldFirstName123")
      expect(changed).not_to have_key("fldEmail123")
      expect(changed).not_to have_key("fldNotes123")
    end
  end

  describe "#fields_for_create" do
    it "excludes nil values for create operations" do
      record = test_class.new(email: "test@example.com", first_name: nil, notes: "Some notes")

      serializable = record.fields_for_create

      # Nil fields should be excluded (using field IDs as keys)
      expect(serializable).to have_key("fldEmail123")
      expect(serializable).to have_key("fldNotes123")
      expect(serializable).not_to have_key("fldFirstName123")
    end

    it "includes non-nil values" do
      record = test_class.new(email: "test@example.com", first_name: "John", notes: "Some notes")

      serializable = record.fields_for_create

      # Using field IDs as keys
      expect(serializable["fldEmail123"]).to eq("test@example.com")
      expect(serializable["fldFirstName123"]).to eq("John")
      expect(serializable["fldNotes123"]).to eq("Some notes")
    end
  end

  describe "#destroy" do
    let(:connection) { instance_double(Faraday::Connection) }

    before do
      client = instance_double(Airtable::ORM::Http::Client, connection: connection)
      allow(client).to receive(:escape).and_return(table_id)
      allow(test_class).to receive(:client).and_return(client)
    end

    def build_persisted_record(**attrs)
      record = test_class.new(**attrs)
      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information
      record
    end

    it "raises for new records" do
      record = test_class.new(email: "test@example.com")
      expect { record.destroy }.to raise_error(Airtable::ORM::RecordNotDestroyed, /Cannot destroy a new record/)
    end

    it "makes a DELETE API call and freezes the record" do
      record = build_persisted_record(email: "test@example.com")

      response = instance_double(Faraday::Response, success?: true, body: { "id" => "rec123", "deleted" => true })
      expect(connection).to receive(:delete).and_return(response)

      result = record.destroy
      expect(result).to eq(record)
      expect(record.persisted?).to be false
      expect(record).to be_frozen
    end

    it "raises ApiError on failure" do
      record = build_persisted_record(email: "test@example.com")

      error_body = { "error" => { "type" => "NOT_FOUND", "message" => "Record not found" } }
      response = instance_double(Faraday::Response, success?: false, status: 404, body: error_body)
      expect(connection).to receive(:delete).and_return(response)

      expect { record.destroy }.to raise_error(Airtable::ORM::ApiError)
    end
  end

  describe "#reload" do
    let(:connection) { instance_double(Faraday::Connection) }

    before do
      client = instance_double(Airtable::ORM::Http::Client, connection: connection)
      allow(client).to receive(:escape).and_return(table_id)
      allow(test_class).to receive(:client).and_return(client)
    end

    it "raises for new records" do
      record = test_class.new(email: "test@example.com")
      expect { record.reload }.to raise_error(Airtable::ORM::RecordNotPersisted, /Cannot reload a new record/)
    end

    it "fetches fresh data from the API and updates attributes" do
      record = test_class.new(email: "old@example.com")
      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information
      record.email = "locally-changed@example.com"

      api_response = {
        "id" => "rec123",
        "createdTime" => "2024-06-15T12:00:00.000Z",
        "fields" => { "fldEmail123" => "fresh@example.com", "fldFirstName123" => "Fresh" }
      }
      response = instance_double(Faraday::Response, success?: true, body: api_response)
      expect(connection).to receive(:get).and_return(response)

      result = record.reload
      expect(result).to eq(record)
      expect(record.email).to eq("fresh@example.com")
      expect(record.first_name).to eq("Fresh")
      expect(record.changed?).to be false
    end
  end

  describe "#update_record behavior with nil values" do
    let(:connection) { instance_double(Faraday::Connection) }
    let(:response) { instance_double(Faraday::Response, success?: true, body: response_body) }
    let(:response_body) do
      {
        "id" => "rec123",
        "createdTime" => "2024-01-01T00:00:00.000Z",
        "fields" => {
          "fldEmail123" => "test@example.com",
          "fldFirstName123" => nil,
          "fldNotes123" => "Some notes"
        }
      }
    end

    before do
      # Stub the HTTP client
      client = instance_double(Airtable::ORM::Http::Client, connection: connection)
      allow(client).to receive(:escape).and_return(table_id)
      allow(test_class).to receive(:client).and_return(client)
    end

    it "sends nil values to API for fields changed to nil" do
      record = test_class.new(email: "test@example.com", first_name: "John", notes: "Some notes")
      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information

      # Change first_name to nil
      record.first_name = nil

      # Expect PATCH request with nil value (using field ID as key)
      expect(connection).to receive(:patch) do |path, body|
        expect(path).to eq(test_class.api_path("rec123"))
        expect(body[:fields]).to eq({ "fldFirstName123" => nil })
        response
      end

      record.save
    end

    it "does not send unchanged fields even if they are nil" do
      record = test_class.new(email: "test@example.com", first_name: nil, notes: "Some notes")
      record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
      record.clear_changes_information

      # Change only notes
      record.notes = "Updated notes"

      # Expect PATCH request without first_name (even though it's nil), using field IDs
      expect(connection).to receive(:patch) do |path, body|
        expect(path).to eq(test_class.api_path("rec123"))
        expect(body[:fields]).to eq({ "fldNotes123" => "Updated notes" })
        expect(body[:fields]).not_to have_key("fldFirstName123")
        response
      end

      record.save
    end
  end

  describe "#save error handling" do
    let(:connection) { instance_double(Faraday::Connection) }

    before do
      client = instance_double(Airtable::ORM::Http::Client, connection: connection)
      allow(client).to receive(:escape).and_return(table_id)
      allow(test_class).to receive(:client).and_return(client)
    end

    def persisted_record
      test_class.new(email: "test@example.com").tap do |record|
        record.send(:assign_persistence_state, id: "rec123", created_at: Time.current, persisted: true)
        record.clear_changes_information
        record.email = "changed@example.com"
      end
    end

    # ConnectionError is a sibling of ApiError, so save's `rescue ApiError` doesn't catch it — a
    # transport blip propagates (for the job's retry_on to retry) instead of being swallowed into a
    # silent false. This example guards that hierarchy: make ConnectionError < ApiError again and it fails.
    it "lets Airtable::ORM::ConnectionError propagate instead of swallowing it into false" do
      allow(connection).to receive(:patch).and_raise(Airtable::ORM::ConnectionError.new("Airtable request failed"))

      expect { persisted_record.save }.to raise_error(Airtable::ORM::ConnectionError)
    end

    it "still swallows a genuine Airtable::ORM::ApiError (HTTP error response) into false" do
      allow(connection).to receive(:patch).and_raise(Airtable::ORM::ApiError.new("HTTP 500", status: 500))

      expect(persisted_record.save).to be(false)
    end
  end
end
