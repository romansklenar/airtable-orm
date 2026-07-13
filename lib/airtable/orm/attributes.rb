# frozen_string_literal: true

module Airtable
  module ORM
    module Attributes
      extend ActiveSupport::Concern

      included do
        include ActiveModel::Attributes
        # The `normalizes` DSL ships with ActiveModel 8.0+; on 7.1 models simply don't have it.
        include ActiveModel::Attributes::Normalization if defined?(ActiveModel::Attributes::Normalization)
        include ActiveModel::Dirty

        # Full symbol → field_id mapping from config/airtable.yml (includes ALL fields).
        # Use field_mapping instead, which filters to only declared attributes.
        class_attribute :config_field_mapping, instance_writer: false, default: {}
      end

      # Special read-only attributes that are not part of the Airtable fields
      READ_ONLY_ATTRIBUTES = %i[id created_at].freeze

      class_methods do
        # Set the logical table name (symbol) for this model.
        # This triggers config field mapping from config.
        def table_name=(symbol)
          @table_name = symbol.to_sym
          define_field_mapping
        end

        def table_name
          @table_name
        end

        # Filtered mapping: only symbols that have a declared `attribute` in the model.
        # Lazily computed on first access (after class body has been evaluated).
        def field_mapping
          @field_mapping ||= config_field_mapping.select { |symbol, _| attribute_types.key?(symbol.to_s) }
        end

        # Get the Airtable table ID for this model
        def table_id
          ORM.config.table_id(table_name)
        end

        # Get schema for this table
        # Memoized at class level to avoid repeated cache lookups
        def schema
          return {} unless table_name

          @schema ||= Airtable::ORM::Schema.fetch(base_id)[table_id] || raise(
            Airtable::ORM::ConfigurationError,
            "No table #{table_id.inspect} (#{table_name.inspect}) in the fetched schema for base " \
            "#{base_id.inspect} — check config.tables against the Airtable base"
          )
        end

        # Clear the memoized schema cache
        # Useful for testing or when the schema changes
        def clear_schema_cache
          @schema = nil
          @field_mapping = nil
        end

        # Get field schema by symbol
        def field_schema(symbol)
          field_id = field_mapping[symbol.to_sym]
          return nil unless field_id

          schema.dig(:fields, field_id)
        end

        # Extract select options from schema for singleSelect and multipleSelects fields
        # Returns a hash mapping field symbols to their available options
        #
        # @return [Hash{Symbol => Array<String>}] Field symbols mapped to option arrays
        # @example
        #   Airtable::Case.schema_options
        #   # => { state: ["Open", "Closed"], scope: ["Inquiry", "Claim"], ... }
        #
        # @example Accessing specific field options
        #   Airtable::Case.schema_options[:state]
        #   # => ["Open", "Closed", "Archived"]
        def schema_options
          return {} unless field_mapping.present?

          field_mapping.each_with_object({}) do |(symbol, field_id), options|
            field_info = schema.dig(:fields, field_id)
            next unless field_info

            case field_info[:type]
            when "singleSelect", "multipleSelects"
              choices = field_info.dig(:options, :choices)
              options[symbol] = choices.map { |choice| choice[:name] } if choices
            end
          end
        end

        # Get options for a specific select field
        # @param field_symbol [Symbol] The field symbol (e.g., :category, :state)
        # @return [Array<String>] Array of available options for the field
        # @example
        #   Airtable::Case.field_options(:category)
        #   # => ["Personal Injury", "Property", "Business"]
        def field_options(field_symbol)
          schema_options[field_symbol.to_sym] || []
        end

        private

        # Build config_field_mapping (symbol → field_id) from config.
        # Stores ALL config fields; field_mapping lazily filters to declared attributes.
        def define_field_mapping
          fields = ORM.config.table_fields(table_name)
          self.config_field_mapping = fields&.except(:_id) || {}
        end
      end

      # Override [] to use symbol keys only
      def [](key)
        validate_symbol_key!(key)

        # Handle special read-only attributes
        return read_special_attribute(key) if special_attribute?(key)

        validate_regular_attribute!(key)
        public_send(key)
      end

      # Override []= to use symbol keys only
      def []=(key, value)
        validate_symbol_key!(key)
        validate_not_readonly!(key)
        validate_regular_attribute!(key)

        public_send("#{key}=", value)
      end

      # @api private — Direct access to @attributes, bypassing accessor methods.
      # Used by Associations to avoid infinite recursion when association name matches the attribute.
      def read_raw_attribute(key)
        return nil unless attribute_defined?(key)

        @attributes[key.to_s]&.value
      end

      # @api private — Direct write to @attributes, maintaining Dirty tracking.
      def write_raw_attribute(key, value)
        return unless attribute_defined?(key)

        @attributes.write_from_user(key.to_s, value)
      end

      # Get all attributes as a hash with symbol keys.
      # Delegates to ActiveModel::Attributes#attributes which returns the same data with string keys.
      def symbol_attributes
        attributes.symbolize_keys
      end

      # Non-nil attributes with field IDs as keys (for CREATE).
      def fields_for_create
        map_attributes(key_type: :field_id, exclude_nil: true)
      end

      # Changed attributes with field IDs as keys (for UPDATE). Includes nil values.
      def fields_for_update
        map_attributes(key_type: :field_id, filter: ->(symbol) { changed.include?(symbol.to_s) })
      end

      def map_attributes(key_type:, exclude_nil: false, filter: nil)
        return {} unless self.class.field_mapping

        self.class.field_mapping.each_with_object({}) do |(symbol, field_id), hash|
          next if filter && !filter.call(symbol)

          value = read_raw_attribute(symbol)
          next if exclude_nil && value.nil?

          key = key_type == :symbol ? symbol : field_id
          hash[key] = value
        end
      end

      # Validate that key is a symbol
      def validate_symbol_key!(key)
        return if key.is_a?(Symbol)

        raise Airtable::ORM::InvalidAttributeError, "Only symbol keys are supported (e.g., record[:email])"
      end

      # Validate that key is not a read-only attribute
      def validate_not_readonly!(key)
        return unless READ_ONLY_ATTRIBUTES.include?(key)

        raise Airtable::ORM::InvalidAttributeError, "Cannot set read-only attribute: #{key.inspect}"
      end

      # Validate that key is a known regular attribute (not special attributes like :id, :created_at)
      def validate_regular_attribute!(key)
        return if attribute_defined?(key)

        raise Airtable::ORM::UnknownFieldError, "Unknown field symbol: #{key.inspect}"
      end

      # Check if this is a special read-only attribute
      def special_attribute?(key)
        READ_ONLY_ATTRIBUTES.include?(key)
      end

      # Read a special read-only attribute value
      def read_special_attribute(key)
        case key
        when :id then @id
        when :created_at then @created_at
        end
      end

      # Check if attribute is defined (explicitly declared in the model class body)
      def attribute_defined?(symbol)
        self.class.attribute_types.key?(symbol.to_s)
      end

      # Custom type for Airtable arrays (handles record links and multi-selects)
      class AirtableArrayType < ActiveModel::Type::Value
        def cast(value)
          case value
          when Array then value
          when nil then []
          else [value]
          end
        end

        def serialize(value)
          cast(value)
        end
      end

      ActiveModel::Type.register(:airtable_array, AirtableArrayType)
    end
  end
end
