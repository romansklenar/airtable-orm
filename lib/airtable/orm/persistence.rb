# frozen_string_literal: true

require "time"

module Airtable
  module ORM
    module Persistence
      extend ActiveSupport::Concern

      included do
        attr_reader :id, :created_at

        # Track if this record has been persisted to Airtable
        define_model_callbacks :save, :create, :update, :destroy
      end

      BATCH_SIZE = 10
      MAX_FIND_MANY_IDS = 500

      # Airtable record IDs: rec + alphanumeric characters. Validated before any ID reaches
      # a URL path or formula interpolation (injection guard).
      RECORD_ID_FORMAT = /\Arec[a-zA-Z0-9_-]+\z/

      class_methods do
        # Batch update records (up to 10 per API request).
        # Triages locally: new/invalid → failed, unchanged → skipped, changed → sent.
        def update_many(records)
          result = Airtable::ORM::BatchResult.new

          pending = []
          records.each do |record|
            if record.new_record? || record.invalid?
              result.failed << record
            elsif !record.changed?
              record.clear_changes_information
              result.skipped << record
            else
              pending << record
            end
          end

          pending.each_slice(BATCH_SIZE) do |batch|
            send_batch_update(batch, result)
          end

          result
        end

        # Get the API client
        def client
          Airtable::ORM::Http::Client.default
        end

        # Build API path for this table (appends returnFieldsByFieldId=true).
        def api_path(resource_id = nil)
          base_path = "/v0/#{ORM.config.base_id}/#{client.escape(table_id)}"
          full_path = resource_id ? "#{base_path}/#{resource_id}" : base_path
          "#{full_path}?returnFieldsByFieldId=true"
        end

        # Find a record by ID. Rejects malformed IDs up front — an ID that can never exist
        # must not reach the URL path (nil would hit the LIST endpoint, "recX/.." another one).
        def find(id)
          unless id.to_s.match?(RECORD_ID_FORMAT)
            raise Airtable::ORM::RecordNotFound, "Couldn't find record with id=#{id.inspect}"
          end

          response = client.connection.get(api_path(id))
          parsed_response = response.body

          if response.success?
            instantiate_from_api_response(parsed_response)
          else
            Airtable::ORM::Http::Client.raise_api_error(response.status, parsed_response)
          end
        rescue Airtable::ORM::ApiError => e
          raise Airtable::ORM::RecordNotFound, "Couldn't find record with id=#{id}" if e.status == 404

          raise
        end

        # Find multiple records by IDs, preserving order.
        # Uses an OR formula (single API request) and sorts in memory.
        def find_many(ids)
          return Airtable::ORM::Collection.new([], model_class: self) if ids.empty?

          validated_ids = validate_record_ids(ids)

          if validated_ids.size > MAX_FIND_MANY_IDS
            raise ArgumentError, "find_many supports at most #{MAX_FIND_MANY_IDS} IDs (got #{validated_ids.size})"
          end

          position_hash = validated_ids.each_with_index.to_h

          or_args = validated_ids.map { |id| "RECORD_ID() = '#{id}'" }.join(",")
          formula = "OR(#{or_args})"
          where(formula: formula).sort_by { |record| position_hash[record.id] || validated_ids.length }
        end

        # Create a new record and save it
        def create(attributes = {})
          record = new(attributes)
          record.save
          record
        end

        # Create a new record and save it, raising an error if validation fails
        def create!(attributes = {})
          record = new(attributes)
          record.save!
          record
        end

        # Instantiate a record from API response
        def instantiate_from_api_response(response)
          data = response.with_indifferent_access
          symbol_attrs = fields_to_symbol_attributes(data[:fields])

          record = new(**symbol_attrs)
          record.send(:assign_persistence_state,
                      id: data[:id],
                      created_at: data[:createdTime] ? Time.iso8601(data[:createdTime].to_s) : nil,
                      persisted: true)
          record.clear_changes_information

          record
        end

        # Convert API field IDs to symbol attributes.
        # field_mapping already contains only declared attributes.
        def fields_to_symbol_attributes(fields)
          return {} unless fields.is_a?(Hash)

          field_mapping.each_with_object({}) do |(symbol, field_id), hash|
            hash[symbol] = fields[field_id] if fields.key?(field_id)
          end
        end

        private

        # Send a single batch PATCH request to Airtable.
        def send_batch_update(batch, result)
          body = {
            records: batch.map { |record| { id: record.id, fields: record.fields_for_update } }
          }

          response = client.connection.patch(api_path, body)
          parsed = response.body

          if response.success?
            parsed = parsed.with_indifferent_access if parsed.is_a?(Hash)
            response_records = parsed[:records] || []
            response_by_id = response_records.index_by { |r| r[:id] }

            batch.each do |record|
              record_data = response_by_id[record.id]
              if record_data
                record.send(:apply_response_fields, record_data)
                result.updated << record
              else
                result.failed << record
              end
            end
          else
            batch.each { |record| result.failed << record }
            error_message = parsed.is_a?(Hash) ? parsed.with_indifferent_access.dig(:error, :message) : parsed
            ORM.config.logger.error(
              "Airtable batch update failed: HTTP #{response.status}: #{error_message.to_s.truncate(200)}"
            )
          end
        rescue Airtable::ORM::ApiError => e
          batch.each { |record| result.failed << record }
          ORM.config.logger.error("Airtable batch update error: #{e.message}")
        end

        # Validate that record IDs match Airtable's format to prevent formula injection
        def validate_record_ids(ids)
          ids.map do |id|
            id_str = id.to_s
            unless id_str.match?(RECORD_ID_FORMAT)
              raise ArgumentError,
                    "Invalid Airtable record ID: #{id_str.inspect}"
            end

            id_str
          end
        end
      end

      # Initialize a record with symbol attributes
      # Usage: new(email: "test@example.com", first_name: "John")
      def initialize(**attributes)
        # Initialize as a new record (not persisted, not destroyed)
        @id = nil
        @created_at = nil
        @persisted = false
        @destroyed = false
        @previously_new_record = false

        # Initialize ActiveModel::Attributes
        super()

        # Set attributes using ActiveModel's assign_attributes
        assign_attributes(attributes) if attributes.present?
      end

      # Check if this is a new record (not yet saved)
      def new_record?
        !@persisted && !@destroyed
      end

      # Check if this record has been saved
      def persisted?
        @persisted == true
      end

      # Check if this record has been destroyed
      def destroyed?
        @destroyed == true
      end

      # Check if this record was new before the last save
      def previously_new_record?
        @previously_new_record == true
      end

      # Save the record (create or update)
      def save(validate: true)
        return false if validate && invalid?

        result = run_callbacks(:save) do
          new_record? ? create_record : update_record
        end

        result != false
      rescue Airtable::ORM::ApiError
        false
      end

      # Save the record, raising an error if it fails.
      # Unlike save, lets ApiError propagate with full error details.
      def save!(validate: true)
        raise Airtable::ORM::RecordInvalid, self if validate && invalid?

        result = run_callbacks(:save) do
          new_record? ? create_record : update_record
        end

        raise Airtable::ORM::RecordNotSaved, "Failed to save the record" if result == false

        true
      end

      # Update attributes and save
      def update(attributes)
        assign_attributes(attributes)
        save
      end

      # Update attributes and save, raising an error if it fails
      def update!(attributes)
        assign_attributes(attributes)
        save!
      end

      # Destroy the record
      def destroy
        raise Airtable::ORM::RecordNotDestroyed, "Cannot destroy a new record" if new_record?

        run_callbacks :destroy do
          response = client.connection.delete(self.class.api_path(id))
          parsed_response = response.body

          if response.success?
            @persisted = false
            @destroyed = true
            freeze
            self
          else
            Airtable::ORM::Http::Client.raise_api_error(response.status, parsed_response)
          end
        end
      end

      # Reload the record from the API
      def reload
        raise Airtable::ORM::RecordNotPersisted, "Cannot reload a new record" if new_record?

        fresh_record = self.class.find(id)

        # Copy attributes from fresh record using raw attribute access
        self.class.attribute_types.each_key do |name|
          write_raw_attribute(name.to_sym, fresh_record.read_raw_attribute(name.to_sym))
        end

        @created_at = fresh_record.created_at
        clear_changes_information

        self
      end

      # Assign persistence metadata (id, created_at, persisted flag)
      def assign_persistence_state(id:, created_at:, persisted:)
        @id = id
        @created_at = created_at
        @persisted = persisted
      end

      # Apply response fields from a create, update, or batch operation.
      # Uses changes_applied (not clear_changes_information) so after_save
      # callbacks can inspect previous_changes / saved_change_to_*? methods.
      def apply_response_fields(data)
        @previously_new_record = new_record?

        data = data.with_indifferent_access
        symbol_attrs = self.class.fields_to_symbol_attributes(data[:fields])
        symbol_attrs.each { |key, value| write_raw_attribute(key, value) }

        assign_persistence_state(
          id: data[:id],
          created_at: data[:createdTime] ? Time.iso8601(data[:createdTime].to_s) : nil,
          persisted: true
        )
        changes_applied
      end

      def client
        self.class.client
      end

      # Handle API response from create/update operations
      def handle_persistence_response(response)
        parsed = response.body

        if response.success?
          apply_response_fields(parsed)
        else
          Airtable::ORM::Http::Client.raise_api_error(response.status, parsed)
        end
      end

      # Create a new record via API
      def create_record
        run_callbacks :create do
          body = { fields: fields_for_create }
          response = client.connection.post(self.class.api_path, body)
          handle_persistence_response(response)
          true
        end
      end

      # Update only changed fields via PATCH. Fields changed TO nil are sent
      # (to clear them in Airtable); unchanged nil fields are not sent.
      def update_record
        unless changed?
          clear_changes_information
          return true
        end

        run_callbacks :update do
          body = { fields: fields_for_update }
          response = client.connection.patch(self.class.api_path(id), body)
          handle_persistence_response(response)
          true
        end
      end
    end
  end
end
