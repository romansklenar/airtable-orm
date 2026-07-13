# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Base, :airtable do
  # Mock classes for testing
  class TestAirtableModel < Airtable::ORM::Base
    self.table_name = :client

    attribute :first_name, :string
    attribute :last_name, :string
    attribute :display_name, :string
    attribute :email, :string
    attribute :phone, :string
    attribute :street, :string
    attribute :city, :string
    attribute :zip, :string
    attribute :birth_date, :date
    attribute :bank_account, :string
    attribute :parent_user_ids, :airtable_array
    attribute :case_ids, :airtable_array
  end

  let(:test_record) do
    TestAirtableModel.new(email: "test@example.com", first_name: "John", last_name: "Doe")
  end

  # Helper to create a persisted record (simulating API response)
  def create_persisted_record(id: "rec123", created_at: "2024-01-01T00:00:00.000Z", email: "test@example.com", **kwargs)
    params = kwargs.merge(email: email)
    record = TestAirtableModel.new(**params)
    record.send(:assign_persistence_state, id: id, created_at: Time.iso8601(created_at), persisted: true)
    record.clear_changes_information
    record
  end

  describe "initialization" do
    context "with symbol keys" do
      it "initializes with symbol keys" do
        record = TestAirtableModel.new(email: "test@example.com", first_name: "John")
        expect(record[:email]).to eq("test@example.com")
        expect(record[:first_name]).to eq("John")
      end

      it "creates new record without id and created_at" do
        record = TestAirtableModel.new(email: "test@example.com")
        expect(record.id).to be_nil
        expect(record.created_at).to be_nil
        expect(record.new_record?).to be true
        expect(record[:email]).to eq("test@example.com")
      end
    end

    context "with API response (field IDs)" do
      it "instantiates from API response format" do
        # API returns field IDs when using returnFieldsByFieldId=true
        api_response = {
          "id" => "rec456",
          "createdTime" => "2024-01-01T00:00:00.000Z",
          "fields" => {
            "fldBn8I7io39SblLk" => "api@example.com",
            "fldGL536HB0zxZZk2" => "Jane"
          }
        }

        record = TestAirtableModel.instantiate_from_api_response(api_response)
        expect(record.id).to eq("rec456")
        expect(record.created_at).to be_a(Time)
        expect(record[:email]).to eq("api@example.com")
        expect(record[:first_name]).to eq("Jane")
        expect(record.persisted?).to be true
      end
    end
  end

  describe "symbol-based field access" do
    context "with symbol keys for reading" do
      it "accesses field using symbol key" do
        expect(test_record[:email]).to eq("test@example.com")
      end

      it "accesses field using symbol key for first_name" do
        expect(test_record[:first_name]).to eq("John")
      end

      it "accesses field using symbol key for last_name" do
        expect(test_record[:last_name]).to eq("Doe")
      end

      it "raises error for unknown symbol key" do
        expect { test_record[:unknown_field] }.to raise_error(Airtable::ORM::UnknownFieldError, /Unknown field symbol/)
      end

      it "does not allow string access" do
        expect do
          test_record["E-mail"]
        end.to raise_error(Airtable::ORM::InvalidAttributeError, /Only symbol keys are supported/)
      end

      it "accesses id using symbol key" do
        record = create_persisted_record
        expect(record[:id]).to eq("rec123")
      end

      it "accesses created_at using symbol key" do
        record = create_persisted_record
        expect(record[:created_at]).to be_a(Time)
      end
    end

    context "with symbol keys for writing" do
      it "sets field using symbol key" do
        test_record[:email] = "new@example.com"
        expect(test_record[:email]).to eq("new@example.com")
      end

      it "sets field using symbol key for first_name" do
        test_record[:first_name] = "Jane"
        expect(test_record[:first_name]).to eq("Jane")
      end

      it "raises error for unknown symbol key on write" do
        expect do
          test_record[:unknown_field] = "value"
        end.to raise_error(Airtable::ORM::UnknownFieldError, /Unknown field symbol/)
      end

      it "does not allow string write access" do
        expect do
          test_record["E-mail"] =
            "test@example.com"
        end.to raise_error(Airtable::ORM::InvalidAttributeError, /Only symbol keys are supported/)
      end

      it "does not allow writing to id" do
        expect do
          test_record[:id] = "rec999"
        end.to raise_error(Airtable::ORM::InvalidAttributeError, /Cannot set read-only attribute/)
      end

      it "does not allow writing to created_at" do
        expect do
          test_record[:created_at] =
            Time.current
        end.to raise_error(Airtable::ORM::InvalidAttributeError, /Cannot set read-only attribute/)
      end
    end
  end

  describe "ActiveModel::Dirty integration" do
    it "tracks changes" do
      test_record[:email] = "changed@example.com"
      expect(test_record.changed?).to be true
      expect(test_record.changed).to include("email")
    end

    it "clears changes after initialization" do
      record = create_persisted_record
      expect(record.changed?).to be false
    end
  end

  describe "#symbol_attributes" do
    it "returns all attributes with symbol keys" do
      attrs = test_record.symbol_attributes
      expect(attrs).to be_a(Hash)
      expect(attrs[:email]).to eq("test@example.com")
      expect(attrs[:first_name]).to eq("John")
      expect(attrs[:last_name]).to eq("Doe")
    end
  end

  describe "#fields_for_create" do
    it "returns attributes with field IDs for API" do
      fields = test_record.fields_for_create
      expect(fields).to be_a(Hash)
      expect(fields.keys).to all(be_a(String))
      expect(fields["fldBn8I7io39SblLk"]).to eq("test@example.com")
    end

    it "excludes nil values" do
      record = TestAirtableModel.new(email: "test@example.com")
      fields = record.fields_for_create
      expect(fields["fldBn8I7io39SblLk"]).to eq("test@example.com")
      # Fields with nil values should not be included
      expect(fields.keys.size).to eq(1)
    end
  end

  describe "#to_h" do
    it "returns hash with symbol keys including id and created_at" do
      record = create_persisted_record
      hash = record.to_h

      expect(hash[:id]).to eq("rec123")
      expect(hash[:created_at]).to be_a(Time)
      expect(hash[:email]).to eq("test@example.com")
    end
  end

  describe "#inspect" do
    it "provides readable debug output" do
      record = create_persisted_record(id: "rec123", first_name: "John")
      output = record.inspect

      expect(output).to include("TestAirtableModel")
      expect(output).to include('id: "rec123"')
      expect(output).to include('email: "test@example.com"')
      expect(output).to include('first_name: "John"')
    end
  end

  describe "persistence state" do
    it "identifies new records" do
      expect(test_record.new_record?).to be true
      expect(test_record.persisted?).to be false
    end

    it "identifies persisted records" do
      record = create_persisted_record
      expect(record.new_record?).to be false
      expect(record.persisted?).to be true
    end
  end

  describe "equality" do
    it "compares records by id" do
      record1 = create_persisted_record(id: "rec123")
      record2 = create_persisted_record(id: "rec123", email: "other@example.com")

      expect(record1).to eq(record2)
    end

    it "does not equal records with different ids" do
      record1 = create_persisted_record(id: "rec123")
      record2 = create_persisted_record(id: "rec456")

      expect(record1).not_to eq(record2)
    end

    it "does not equal new records" do
      record1 = TestAirtableModel.new(email: "test@example.com")
      record2 = TestAirtableModel.new(email: "test@example.com")

      expect(record1).not_to eq(record2)
    end
  end

  describe "class methods" do
    describe ".table_name" do
      it "returns the table symbol" do
        expect(TestAirtableModel.table_name).to eq(:client)
      end
    end

    describe ".table_id" do
      it "returns the Airtable table ID" do
        table_id = TestAirtableModel.table_id
        expect(table_id).to be_a(String)
        expect(table_id).to start_with("tbl")
      end
    end

    describe ".schema" do
      it "returns schema for the table" do
        schema = TestAirtableModel.schema
        expect(schema).to be_a(Hash)
        expect(schema).to have_key(:fields)
      end

      it "raises ConfigurationError when the table is missing from the fetched schema" do
        allow(Airtable::ORM::Schema).to receive(:fetch).and_return({})

        expect do
          TestAirtableModel.schema
        end.to raise_error(Airtable::ORM::ConfigurationError, /client/)
      end
    end

    describe ".field_schema" do
      it "returns schema for a specific field" do
        field_schema = TestAirtableModel.field_schema(:email)
        expect(field_schema).to be_a(Hash)
        expect(field_schema[:type]).to eq("singleLineText")
      end
    end
  end

  describe "validations" do
    it "supports ActiveModel validations" do
      # Reuse existing TestAirtableModel with validation
      test_model = Class.new(TestAirtableModel) do
        def self.model_name
          ActiveModel::Name.new(self, nil, "TestValidationModel")
        end

        validates :email, presence: true
      end

      record = test_model.new(first_name: "John")
      expect(record.valid?).to be false
      expect(record.errors[:email]).to be_present
    end
  end

  describe "callbacks" do
    it "supports ActiveModel callbacks" do
      # Just verify the callback mechanism is set up
      expect(TestAirtableModel.ancestors).to include(ActiveModel::Callbacks)
    end
  end

  describe "attribute type casting" do
    it "casts attribute values according to declared types" do
      record = TestAirtableModel.new(birth_date: "2000-01-15")
      expect(record[:birth_date]).to be_a(Date)
      expect(record[:birth_date]).to eq(Date.new(2000, 1, 15))
    end

    it "does not fetch schema for attribute type inference" do
      expect(Airtable::ORM::Schema).not_to receive(:fetch)

      record = TestAirtableModel.new(email: "test@example.com", first_name: "Jane")
      expect(record[:email]).to eq("test@example.com")
      expect(record[:first_name]).to eq("Jane")
    end
  end
end
