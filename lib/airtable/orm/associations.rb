# frozen_string_literal: true

module Airtable
  module ORM
    module Associations
      extend ActiveSupport::Concern

      # Fetch linked records via find_many, slicing to its per-request ID cap so an
      # association (or preload union) with more links than the cap still loads.
      def self.fetch_linked_records(klass, ids)
        records = ids.each_slice(Airtable::ORM::Persistence::MAX_FIND_MANY_IDS)
                     .flat_map { |slice| klass.find_many(slice).to_a }
        Airtable::ORM::Collection.new(records, model_class: klass)
      end

      # Requires Attributes concern. Uses read_raw_attribute/write_raw_attribute to
      # bypass accessors and avoid infinite recursion when association names match attributes.

      included do
        class_attribute :defined_associations, instance_writer: false, default: {}
      end

      private

      # Read linked record IDs from a foreign key, with optional reversal for Airtable UI order.
      # Airtable's API returns record links in reverse order compared to the UI.
      # By default we reverse to match the UI order.
      def read_linked_ids(foreign_key, reverse: true)
        ids = read_raw_attribute(foreign_key) || []
        reverse ? ids.reverse : ids
      end

      # Set memoized value directly (used by preloading)
      def write_association_cache(name, value)
        instance_variable_set(:"@_memo_#{name}", value)
      end

      # Memoize association loading with automatic cache management
      def memoize_association(name)
        ivar = :"@_memo_#{name}"
        return instance_variable_get(ivar) if instance_variable_defined?(ivar)

        instance_variable_set(ivar, yield)
      end

      # Clear memoization cache for an association
      def clear_association_cache(name)
        ivar = :"@_memo_#{name}"
        remove_instance_variable(ivar) if instance_variable_defined?(ivar)
      end

      # Extract ID from a record object or return the ID string as-is
      def extract_association_id(record_or_id)
        record_or_id.respond_to?(:id) ? record_or_id.id : record_or_id
      end

      class_methods do
        # Airtable returns linked IDs in reverse UI order; we reverse on read/write to match.
        def has_many(association_name, class_name:, foreign_key:)
          self.defined_associations = defined_associations.merge(
            association_name => { type: :has_many, class_name: class_name, foreign_key: foreign_key }
          )

          define_method(association_name) do
            memoize_association(association_name) do
              ids = read_linked_ids(foreign_key)
              klass = class_name.constantize
              if ids.empty?
                Airtable::ORM::Collection.new([], model_class: klass)
              else
                Airtable::ORM::Associations.fetch_linked_records(klass, ids)
              end
            end
          end

          define_method("#{association_name}=") do |records|
            ids = Array(records).map { |record| extract_association_id(record) }
            write_raw_attribute(foreign_key, ids.reverse)
            clear_association_cache(association_name)
          end

          define_method("add_#{association_name.to_s.singularize}") do |record|
            current_ids = read_linked_ids(foreign_key, reverse: false)
            add_id = extract_association_id(record)
            write_raw_attribute(foreign_key, [add_id] + current_ids)
            clear_association_cache(association_name)
          end

          define_method("remove_#{association_name.to_s.singularize}") do |record|
            current_ids = read_linked_ids(foreign_key, reverse: false)
            remove_id = extract_association_id(record)

            write_raw_attribute(foreign_key, current_ids - [remove_id])
            clear_association_cache(association_name)
          end
        end

        def belongs_to(association_name, class_name:, foreign_key:)
          self.defined_associations = defined_associations.merge(
            association_name => { type: :belongs_to, class_name: class_name, foreign_key: foreign_key }
          )

          define_method(association_name) do
            memoize_association(association_name) do
              id = read_linked_ids(foreign_key).first
              begin
                id ? class_name.constantize.find(id) : nil
              rescue Airtable::ORM::RecordNotFound
                # A stale link to a deleted record reads as nil, matching the preloaded
                # path (find_many simply omits missing records).
                nil
              end
            end
          end

          define_method("#{association_name}=") do |record|
            if record.nil?
              write_raw_attribute(foreign_key, [])
            else
              id = extract_association_id(record)
              write_raw_attribute(foreign_key, [id])
            end

            clear_association_cache(association_name)
          end
        end

        # In Airtable, linked record fields are stored as ID arrays on both sides,
        # so has_one and belongs_to are functionally identical (unlike ActiveRecord
        # where they differ in which side holds the foreign key).
        alias_method :has_one, :belongs_to

        # Eager-load associations to avoid N+1 API calls.
        def preload(records, *association_names)
          return if records.empty?

          association_names.each do |name|
            config = defined_associations[name]
            raise ArgumentError, "Unknown association: #{name.inspect}" unless config

            klass = config[:class_name].constantize
            fk = config[:foreign_key]
            many = config[:type] == :has_many

            preload_association(records, name, klass, fk, many: many)
          end
        end

        def preload_association(records, association_name, klass, foreign_key, many:)
          all_ids = if many
                      records.flat_map { |r| r.send(:read_linked_ids, foreign_key) }.uniq
                    else
                      records.filter_map { |r| r.send(:read_linked_ids, foreign_key).first }.uniq
                    end

          fetched_by_id =
            if all_ids.empty?
              {}
            else
              Airtable::ORM::Associations.fetch_linked_records(klass, all_ids).index_by(&:id)
            end

          records.each do |record|
            ids = record.send(:read_linked_ids, foreign_key)
            value = if many
                      Airtable::ORM::Collection.new(ids.filter_map { |id| fetched_by_id[id] }, model_class: klass)
                    else
                      fetched_by_id[ids.first]
                    end
            record.send(:write_association_cache, association_name, value)
          end
        end
      end
    end
  end
end
