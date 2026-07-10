# frozen_string_literal: true

module Airtable
  module ORM
    # Thin wrapper around Array that enables chainable preloading.
    #
    #   cases = Airtable::Case.all.preload(:clients)
    #   active = cases.select { |c| c[:state] == "Active" }.preload(:advisors)
    #
    # Filtering methods (select, reject, sort_by) return new Collections,
    # preserving the ability to chain preload.
    class Collection < DelegateClass(Array)
      attr_reader :model_class

      def initialize(records, model_class:)
        super(records)
        @model_class = model_class
      end

      # Eager-load associations for every record in the collection.
      # Returns +self+ so calls can be chained.
      def preload(*names)
        model_class.preload(self, *names)
        self
      end

      def select(&block)
        return super unless block

        self.class.new(super, model_class: model_class)
      end

      def reject(&block)
        return super unless block

        self.class.new(super, model_class: model_class)
      end

      def sort_by(&block)
        return super unless block

        self.class.new(super, model_class: model_class)
      end
    end
  end
end
