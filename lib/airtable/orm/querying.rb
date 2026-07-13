# frozen_string_literal: true

module Airtable
  module ORM
    module Querying
      extend ActiveSupport::Concern

      DEFAULT_PAGE_SIZE = 100
      DEFAULT_MAX_RECORDS = 1000

      class_methods do
        # Fetch all records from the table. Always ignores max_records; use +where+ for limits.
        def all(**options)
          where(**options, max_records: nil)
        end

        # Query records with a formula
        def where(formula: nil, sort: nil, view: nil, fields: nil, max_records: DEFAULT_MAX_RECORDS,
                  page_size: DEFAULT_PAGE_SIZE)
          records(formula:, sort:, view:, fields:, max_records:, page_size:)
        end

        # Fetch the first record matching the criteria
        def first(formula: nil, sort: nil)
          where(formula:, sort:, max_records: 1).first
        end

        # Fetch the last record matching the criteria by reversing the sort order.
        # NOTE: Unlike ActiveRecord, Airtable has no default sort order.
        # Calling last without sort returns an arbitrary record (same as first).
        def last(formula: nil, sort: nil)
          where(formula:, sort: reverse_sort_order(sort), max_records: 1).first
        end

        # Find the first record matching attribute conditions.
        # Example: Airtable::Case.find_by(slug: "abc-123")
        def find_by(**conditions)
          raise ArgumentError, "find_by requires at least one condition" if conditions.empty?

          clauses = conditions.map do |field, value|
            "{#{formula_field_reference(field)}} = #{format_formula_value(value)}"
          end
          formula = clauses.size == 1 ? clauses.first : "AND(#{clauses.join(", ")})"
          first(formula: formula)
        end

        # Like find_by but raises RecordNotFound when no match.
        def find_by!(**conditions)
          find_by(**conditions) || raise(Airtable::ORM::RecordNotFound,
                                         "Couldn't find #{name} with #{conditions.inspect}")
        end

        # Count records without instantiating model objects.
        # Requests no fields to minimize payload (Airtable has no count-only endpoint).
        def count(formula: nil)
          count_records(formula:)
        end

        # Format a Ruby value for use in an Airtable formula comparison.
        # Returns the correctly typed formula literal (quoted string, bare number, function call, etc.).
        def format_formula_value(value)
          case value
          when NilClass then "BLANK()"
          when TrueClass then "TRUE()"
          when FalseClass then "FALSE()"
          when Integer, Float then value.to_s
          # Time/DateTime before Date: DateTime is a Date subclass and must be UTC-normalized.
          when Time, DateTime then "'#{value.getutc.iso8601}'"
          when Date then "'#{value.iso8601}'"
          else "'#{escape_formula_value(value)}'"
          end
        end

        # Escape a value for use in an Airtable formula string literal.
        # Only backslashes and single quotes — Airtable formula string literals have no
        # escape sequences for control characters, so a newline stays a real newline.
        def escape_formula_value(value)
          value.to_s
               .gsub("\\", "\\\\\\\\")  # backslashes first
               .gsub("'", "\\\\'")      # single quotes
        end

        private

        # Fetch records from the API
        def records(formula: nil, sort: nil, view: nil, fields: nil, max_records: nil, page_size: nil, offset: nil,
                    paginate: true)
          all_records = []

          each_page(formula:, sort:, view:, fields:, max_records:, page_size:, offset:, paginate:) do |page|
            all_records.concat(page.map { |record_data| instantiate_from_api_response(record_data) })
          end

          Airtable::ORM::Collection.new(all_records, model_class: self)
        end

        # Count records without instantiating model objects.
        def count_records(formula: nil)
          total = 0
          each_page(formula:, fields: []) { |page| total += page.size }
          total
        end

        # Paginate through listRecords, yielding each page's raw records array.
        def each_page(formula: nil, sort: nil, view: nil, fields: nil, max_records: nil, page_size: nil, offset: nil,
                      paginate: true)
          current_offset = offset

          loop do
            options = build_query_options(formula:, sort:, view:, fields:, max_records:, page_size:,
                                          offset: current_offset)
            response = client.connection.post(api_path("listRecords"), options)
            parsed_response = response.body

            Airtable::ORM::Http::Client.raise_api_error(response.status, parsed_response) unless response.success?

            yield parsed_response["records"]

            break unless paginate && parsed_response["offset"]

            current_offset = parsed_response["offset"]
          end
        end

        # Build query options for the API
        def build_query_options(formula:, sort:, view:, fields:, max_records:, page_size:, offset:)
          {
            returnFieldsByFieldId: true,
            filterByFormula: formula,
            sort: sort && normalize_sort_options(sort),
            view: view,
            fields: fields && resolve_field_ids(fields),
            maxRecords: max_records,
            pageSize: page_size,
            offset: offset
          }.compact
        end

        # Normalize sort options to Airtable API format
        # Accepts: { field: :asc } or [[:field1, :desc], [:field2, :asc]]
        # Converts symbol attributes to their Airtable field IDs
        def normalize_sort_options(sort)
          raise_invalid_sort(sort) unless sort.is_a?(Hash) || sort.is_a?(Array)

          sort.map { |field, direction| { field: resolve_field_id(field), direction: direction.to_s } }
        end

        # Resolve symbol attribute to Airtable field ID
        # If the field is already a string, return it as-is (assuming it's a valid field ID)
        # If it's a symbol, look up the field ID from the attribute map and validate it exists
        def resolve_field_id(field)
          return field.to_s unless field.is_a?(Symbol)

          field_id = field_mapping[field]
          return field_id if field_id

          # Raise error for unknown field symbols to prevent silent API errors
          valid_fields = field_mapping.keys.join(", ")
          raise ArgumentError, "Unknown field: #{field.inspect}. Valid fields: #{valid_fields}"
        end

        # Resolve an array of fields (symbols or strings) to field IDs
        def resolve_field_ids(fields)
          fields.map { |field| resolve_field_id(field) }
        end

        # Resolve a field for interpolation inside {} in a formula. Braces would terminate
        # the reference and let a user-supplied field name inject arbitrary formula clauses.
        def formula_field_reference(field)
          field_id = resolve_field_id(field)
          raise ArgumentError, "Invalid field reference for formula: #{field_id.inspect}" if field_id.match?(/[{}]/)

          field_id
        end

        # Reverse sort order for last() method
        def reverse_sort_order(sort)
          return nil unless sort

          flip = ->(dir) { dir.to_sym == :asc ? :desc : :asc }

          case sort
          when Hash then sort.transform_values(&flip)
          when Array then sort.map { |field, dir| [field, flip.call(dir)] }
          else raise_invalid_sort(sort)
          end
        end

        def raise_invalid_sort(sort)
          raise ArgumentError,
                "sort must be a Hash or Array of [field, direction] pairs, got #{sort.inspect}"
        end
      end
    end
  end
end
