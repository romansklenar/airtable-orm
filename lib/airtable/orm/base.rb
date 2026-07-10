# frozen_string_literal: true

# Load error classes and value objects first
require_relative "errors"
require_relative "batch_result"

module Airtable
  module ORM
    class Base
      include ActiveModel::Model
      include Core
      include Attributes
      include Persistence
      include Querying
      include Associations

      # Callback support
      extend ActiveModel::Callbacks

      class << self
        # Get the base ID from config
        def base_id
          ORM.config.base_id
        end
      end

      # Public deeplink to this record in the Airtable UI.
      def url
        "https://airtable.com/#{self.class.base_id}/#{self.class.table_id}/#{id}"
      end
    end
  end
end
