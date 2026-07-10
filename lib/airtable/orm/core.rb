# frozen_string_literal: true

module Airtable
  module ORM
    module Core
      extend ActiveSupport::Concern

      # Instance comparison
      def ==(other)
        return false unless other.is_a?(self.class)
        return false if new_record? || other.new_record?

        id == other.id
      end

      alias eql? ==

      def hash
        [self.class, id].hash
      end

      # Inspect method for better debugging
      def inspect
        attribute_string = self.class.attribute_types.map do |name, _type|
          value = read_raw_attribute(name.to_sym)
          "#{name}: #{value.inspect}"
        end.join(", ")

        "#<#{self.class.name} id: #{id.inspect}, #{attribute_string}>"
      end

      # Convert to hash with symbol keys
      def to_h
        {
          id: id,
          created_at: created_at,
          **symbol_attributes
        }
      end

      # Freeze the record
      def freeze
        @id.freeze
        @created_at.freeze
        super
      end
    end
  end
end
