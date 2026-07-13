# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Querying, :airtable do
  # Test model for querying
  class TestQueryModel < Airtable::ORM::Base
    self.table_name = :client

    attribute :email, :string
    attribute :first_name, :string
  end

  EMAIL_FIELD_ID = "fldBn8I7io39SblLk"
  FIRST_NAME_FIELD_ID = "fldGL536HB0zxZZk2"

  describe ".all" do
    it "returns all records" do
      stub_list_records(
        records: [
          { id: "rec1", fields: { EMAIL_FIELD_ID => "test1@example.com" }, createdTime: "2024-01-01T00:00:00.000Z" },
          { id: "rec2", fields: { EMAIL_FIELD_ID => "test2@example.com" }, createdTime: "2024-01-02T00:00:00.000Z" }
        ]
      )

      records = TestQueryModel.all
      expect(records.size).to eq(2)
      expect(records.first[:email]).to eq("test1@example.com")
      expect(records.last[:email]).to eq("test2@example.com")
    end

    it "returns empty array when no records" do
      stub_list_records(records: [])

      records = TestQueryModel.all
      expect(records).to eq([])
    end

    it "accepts formula parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{E-mail} = 'test@example.com'"
        }
      )

      TestQueryModel.all(formula: "{E-mail} = 'test@example.com'")
    end

    it "accepts sort parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["sort"] == [{ "field" => EMAIL_FIELD_ID, "direction" => "asc" }]
        }
      )

      TestQueryModel.all(sort: { email: :asc })
    end
  end

  describe ".where" do
    it "filters records with formula" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "admin@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "FIND('admin', {E-mail}) > 0"
        }
      )

      records = TestQueryModel.where(formula: "FIND('admin', {E-mail}) > 0")
      expect(records.size).to eq(1)
    end

    it "accepts view parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["view"] == "Active Users"
        }
      )

      TestQueryModel.where(view: "Active Users")
    end

    it "accepts fields parameter with symbols" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["fields"] == [EMAIL_FIELD_ID, FIRST_NAME_FIELD_ID]
        }
      )

      TestQueryModel.where(fields: %i[email first_name])
    end

    it "accepts fields parameter with string field IDs" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["fields"] == [EMAIL_FIELD_ID]
        }
      )

      TestQueryModel.where(fields: [EMAIL_FIELD_ID])
    end

    it "accepts max_records parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["maxRecords"] == 5
        }
      )

      TestQueryModel.where(max_records: 5)
    end

    it "accepts page_size parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["pageSize"] == 10
        }
      )

      TestQueryModel.where(page_size: 10)
    end
  end

  describe ".first" do
    it "returns first record" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "first@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["maxRecords"] == 1
        }
      )

      record = TestQueryModel.first
      expect(record[:email]).to eq("first@example.com")
    end

    it "returns nil when no records" do
      stub_list_records(records: [])

      record = TestQueryModel.first
      expect(record).to be_nil
    end

    it "accepts formula parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "admin@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{E-mail} = 'admin@example.com'" && body["maxRecords"] == 1
        }
      )

      TestQueryModel.first(formula: "{E-mail} = 'admin@example.com'")
    end

    it "accepts sort parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["sort"] == [{ "field" => EMAIL_FIELD_ID, "direction" => "asc" }]
        }
      )

      TestQueryModel.first(sort: { email: :asc })
    end
  end

  describe ".last" do
    it "returns last record by reversing sort" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "last@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["maxRecords"] == 1
        }
      )

      record = TestQueryModel.last
      expect(record[:email]).to eq("last@example.com")
    end

    it "returns nil when no records" do
      stub_list_records(records: [])

      record = TestQueryModel.last
      expect(record).to be_nil
    end

    it "reverses sort order for hash sort" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          # asc should be reversed to desc
          body["sort"] == [{ "field" => EMAIL_FIELD_ID, "direction" => "desc" }]
        }
      )

      TestQueryModel.last(sort: { email: :asc })
    end

    it "reverses sort order for array sort" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["sort"] == [
            { "field" => EMAIL_FIELD_ID, "direction" => "desc" },
            { "field" => FIRST_NAME_FIELD_ID, "direction" => "asc" }
          ]
        }
      )

      TestQueryModel.last(sort: [%i[email asc], %i[first_name desc]])
    end
  end

  describe ".find_by" do
    it "returns the first record matching a single condition" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{EMAIL_FIELD_ID}} = 'test@example.com'" && body["maxRecords"] == 1
        }
      )

      record = TestQueryModel.find_by(email: "test@example.com")
      expect(record[:email]).to eq("test@example.com")
    end

    it "returns nil when no match" do
      stub_list_records(records: [])

      record = TestQueryModel.find_by(email: "nonexistent@example.com")
      expect(record).to be_nil
    end

    it "builds AND formula for multiple conditions" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com", FIRST_NAME_FIELD_ID => "John" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "AND({#{EMAIL_FIELD_ID}} = 'test@example.com', {#{FIRST_NAME_FIELD_ID}} = 'John')"
        }
      )

      TestQueryModel.find_by(email: "test@example.com", first_name: "John")
    end

    it "escapes single quotes in values" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{FIRST_NAME_FIELD_ID}} = 'O\\'Brien'"
        }
      )

      TestQueryModel.find_by(first_name: "O'Brien")
    end

    it "formats numeric values without quotes" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{EMAIL_FIELD_ID}} = 42"
        }
      )

      TestQueryModel.find_by(email: 42)
    end

    it "formats boolean true as TRUE()" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{EMAIL_FIELD_ID}} = TRUE()"
        }
      )

      TestQueryModel.find_by(email: true)
    end

    it "formats boolean false as FALSE()" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{EMAIL_FIELD_ID}} = FALSE()"
        }
      )

      TestQueryModel.find_by(email: false)
    end

    it "formats nil as BLANK()" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{EMAIL_FIELD_ID}} = BLANK()"
        }
      )

      TestQueryModel.find_by(email: nil)
    end

    it "raises ArgumentError for unknown fields" do
      expect do
        TestQueryModel.find_by(nonexistent_field: "value")
      end.to raise_error(ArgumentError, /Unknown field.*nonexistent_field/)
    end

    it "rejects string field names containing braces to prevent formula injection" do
      expect do
        TestQueryModel.find_by("Email} != BLANK()), OR({Email" => "x")
      end.to raise_error(ArgumentError, /Invalid field reference/)
    end

    it "accepts string field IDs as condition keys" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "{#{EMAIL_FIELD_ID}} = 'test@example.com'"
        }
      )

      TestQueryModel.find_by(EMAIL_FIELD_ID => "test@example.com")
    end
  end

  describe ".format_formula_value" do
    it "formats a DateTime as UTC" do
      value = DateTime.new(2026, 7, 11, 10, 0, 0, "+02:00")
      expect(TestQueryModel.format_formula_value(value)).to eq("'2026-07-11T08:00:00Z'")
    end

    it "formats a Time as UTC without mutating the caller's object" do
      value = Time.new(2026, 7, 11, 10, 0, 0, "+02:00")
      expect(TestQueryModel.format_formula_value(value)).to eq("'2026-07-11T08:00:00Z'")
      expect(value.utc_offset).to eq(7200)
    end

    it "formats a Date as a date literal" do
      expect(TestQueryModel.format_formula_value(Date.new(2026, 7, 11))).to eq("'2026-07-11'")
    end

    it "preserves control characters in string values" do
      # Airtable formula string literals have no escape sequences for control
      # characters — a literal backslash+n would never match a real newline.
      expect(TestQueryModel.format_formula_value("line1\nline2\tend")).to eq("'line1\nline2\tend'")
    end

    it "escapes single quotes and backslashes" do
      expect(TestQueryModel.format_formula_value("O'Brien \\ Co")).to eq("'O\\'Brien \\\\ Co'")
    end
  end

  describe ".find_by!" do
    it "returns the record when found" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "test@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }]
      )

      record = TestQueryModel.find_by!(email: "test@example.com")
      expect(record[:email]).to eq("test@example.com")
    end

    it "raises RecordNotFound when no match" do
      stub_list_records(records: [])

      expect do
        TestQueryModel.find_by!(email: "nonexistent@example.com")
      end.to raise_error(Airtable::ORM::RecordNotFound, /Couldn't find TestQueryModel/)
    end
  end

  describe ".count" do
    it "returns count of matching records" do
      stub_list_records(
        records: [
          { id: "rec1", fields: { EMAIL_FIELD_ID => "test1@example.com" }, createdTime: "2024-01-01T00:00:00.000Z" },
          { id: "rec2", fields: { EMAIL_FIELD_ID => "test2@example.com" }, createdTime: "2024-01-02T00:00:00.000Z" },
          { id: "rec3", fields: { EMAIL_FIELD_ID => "test3@example.com" }, createdTime: "2024-01-03T00:00:00.000Z" }
        ]
      )

      count = TestQueryModel.count
      expect(count).to eq(3)
    end

    it "returns 0 when no records" do
      stub_list_records(records: [])

      count = TestQueryModel.count
      expect(count).to eq(0)
    end

    it "accepts formula parameter" do
      stub_list_records(
        records: [{ id: "rec1", fields: { EMAIL_FIELD_ID => "admin@example.com" },
                    createdTime: "2024-01-01T00:00:00.000Z" }],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["filterByFormula"] == "FIND('admin', {E-mail}) > 0"
        }
      )

      TestQueryModel.count(formula: "FIND('admin', {E-mail}) > 0")
    end
  end

  describe "pagination" do
    it "automatically paginates through all records" do
      # First page
      @stubs.post("/v0/appVntahBV9Q4evA7/tbl8MkbTpROqjERoD/listRecords") do |env|
        body = JSON.parse(env.body)
        if body["offset"].nil?
          [
            200,
            { "Content-Type" => "application/json" },
            {
              records: [
                { id: "rec1", fields: { EMAIL_FIELD_ID => "test1@example.com" },
                  createdTime: "2024-01-01T00:00:00.000Z" },
                { id: "rec2", fields: { EMAIL_FIELD_ID => "test2@example.com" },
                  createdTime: "2024-01-02T00:00:00.000Z" }
              ],
              offset: "page2"
            }.to_json
          ]
        elsif body["offset"] == "page2"
          # Second page
          [
            200,
            { "Content-Type" => "application/json" },
            {
              records: [
                { id: "rec3", fields: { EMAIL_FIELD_ID => "test3@example.com" },
                  createdTime: "2024-01-03T00:00:00.000Z" }
              ]
              # No offset means last page
            }.to_json
          ]
        end
      end

      records = TestQueryModel.all
      expect(records.size).to eq(3)
      expect(records.map { |r| r[:email] }).to eq(["test1@example.com", "test2@example.com", "test3@example.com"])
    end

    it "handles multiple pages correctly" do
      # Simulate 3 pages
      @stubs.post("/v0/appVntahBV9Q4evA7/tbl8MkbTpROqjERoD/listRecords") do |env|
        body = JSON.parse(env.body)
        page = lambda do |id, email, created, offset|
          record = { id: id, fields: { EMAIL_FIELD_ID => email }, createdTime: created }
          [200, { "Content-Type" => "application/json" }, { records: [record], offset: offset }.compact.to_json]
        end

        case body["offset"]
        when nil then page.call("rec1", "p1@example.com", "2024-01-01T00:00:00.000Z", "p2")
        when "p2" then page.call("rec2", "p2@example.com", "2024-01-02T00:00:00.000Z", "p3")
        when "p3" then page.call("rec3", "p3@example.com", "2024-01-03T00:00:00.000Z", nil)
        end
      end

      records = TestQueryModel.all
      expect(records.size).to eq(3)
    end
  end

  describe "sort options normalization" do
    it "normalizes hash sort to API format" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["sort"] == [{ "field" => EMAIL_FIELD_ID, "direction" => "asc" }]
        }
      )

      TestQueryModel.all(sort: { email: :asc })
    end

    it "normalizes array sort to API format" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["sort"] == [
            { "field" => EMAIL_FIELD_ID, "direction" => "desc" },
            { "field" => FIRST_NAME_FIELD_ID, "direction" => "asc" }
          ]
        }
      )

      TestQueryModel.all(sort: [%i[email desc], %i[first_name asc]])
    end

    it "handles nil sort" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          !body.key?("sort")
        }
      )

      TestQueryModel.all(sort: nil)
    end

    it "raises ArgumentError for a sort that is not a Hash or Array" do
      expect do
        TestQueryModel.all(sort: :email)
      end.to raise_error(ArgumentError, /sort must be a Hash or Array/)
    end

    it "raises ArgumentError when last() gets a sort that is not a Hash or Array" do
      expect do
        TestQueryModel.last(sort: :email)
      end.to raise_error(ArgumentError, /sort must be a Hash or Array/)
    end

    it "handles empty hash sort" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["sort"] == []
        }
      )

      TestQueryModel.all(sort: {})
    end

    it "includes returnFieldsByFieldId in POST body" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          body["returnFieldsByFieldId"] == true
        }
      )

      TestQueryModel.all
    end

    it "converts symbols to field IDs for field names" do
      stub_list_records(
        records: [],
        request_matcher: lambda { |request|
          body = JSON.parse(request.body)
          # Should convert :email symbol to field ID
          body["sort"].first["field"].is_a?(String) && body["sort"].first["field"] == EMAIL_FIELD_ID
        }
      )

      TestQueryModel.all(sort: { email: :asc })
    end
  end

  describe "error handling" do
    it "raises ApiError on API errors" do
      @stubs.post("/v0/appVntahBV9Q4evA7/tbl8MkbTpROqjERoD/listRecords") do
        [
          400,
          { "Content-Type" => "application/json" },
          { error: { type: "INVALID_REQUEST", message: "Invalid formula" } }.to_json
        ]
      end

      expect do
        TestQueryModel.where(formula: "INVALID_FORMULA()")
      end.to raise_error(Airtable::ORM::ApiError, /Invalid formula/)
    end

    it "raises ApiError on 404" do
      @stubs.post("/v0/appVntahBV9Q4evA7/tbl8MkbTpROqjERoD/listRecords") do
        [
          404,
          { "Content-Type" => "application/json" },
          { error: { type: "NOT_FOUND", message: "Table not found" } }.to_json
        ]
      end

      expect do
        TestQueryModel.all
      end.to raise_error(Airtable::ORM::ApiError, /Table not found/)
    end

  end

  # Helper to stub list records API call
  def stub_list_records(records:, request_matcher: nil)
    # Use actual test environment IDs from config/airtable.yml (airtable-test section)
    @stubs.post("/v0/appVntahBV9Q4evA7/tbl8MkbTpROqjERoD/listRecords") do |env|
      if request_matcher && !request_matcher.call(env)
        [400, {}, { error: { message: "Request didn't match expected format" } }.to_json]
      else
        [
          200,
          { "Content-Type" => "application/json" },
          { records: records }.to_json
        ]
      end
    end
  end
end
