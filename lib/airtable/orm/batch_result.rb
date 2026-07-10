# frozen_string_literal: true

module Airtable
  module ORM
    # Holds the result of a batch update operation.
    #
    # @attr updated [Array] Records that were successfully sent to the API and updated
    # @attr skipped [Array] Records that had no changes and were not sent to the API
    # @attr failed [Array] Records that failed validation or API call
    BatchResult = Struct.new(:updated, :skipped, :failed, keyword_init: true) do
      def initialize(updated: [], skipped: [], failed: [])
        super
      end

      def none_failed?
        failed.empty?
      end

      def any_failed?
        failed.any?
      end

      def total_count
        updated.size + skipped.size + failed.size
      end
    end
  end
end
