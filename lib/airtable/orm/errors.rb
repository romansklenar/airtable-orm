# frozen_string_literal: true

module Airtable
  module ORM
    # Base error class for all Airtable-related errors
    class Error < StandardError; end

    # Raised when a record cannot be found
    class RecordNotFound < Error; end

    # Raised when trying to access an unknown field
    class UnknownFieldError < Error; end

    # Raised when an invalid attribute is provided
    class InvalidAttributeError < Error; end

    # Raised when the host configuration doesn't match the Airtable base
    # (e.g. a configured table ID absent from the fetched schema)
    class ConfigurationError < Error; end

    # Raised when a record fails validation.
    # Use the #record method to retrieve the record which did not validate.
    class RecordInvalid < Error
      attr_reader :record

      def initialize(record = nil)
        if record
          @record = record
          errors = @record.errors.full_messages.join(", ")
          super("Validation failed: #{errors}")
        else
          super("Record invalid")
        end
      end
    end

    # Raised when trying to perform operations on a non-persisted record
    # (e.g., trying to destroy or reload a new record)
    class RecordNotPersisted < Error; end

    # Raised when trying to save a new record that fails
    class RecordNotSaved < Error; end

    # Raised when a record cannot be destroyed
    class RecordNotDestroyed < Error; end

    # Raised when API communication fails
    class ApiError < Error
      attr_reader :status, :response

      def initialize(message, status: nil, response: nil)
        super(message)
        @status = status
        @response = response
      end
    end

    # Raised when the request never completed — a read timeout, dropped/failed connection, TLS error,
    # etc. — mapped from the raw transport error by Airtable::ORM::Http::ErrorHandler so callers only
    # ever deal in Airtable::* exceptions, never the HTTP client's. Deliberately a sibling of ApiError,
    # not a subclass: the API never responded, so it isn't an "API error". Being outside the ApiError
    # branch also means persistence's `rescue ApiError` ignores it, so a blip propagates (to retry)
    # instead of being swallowed into a `false` save.
    class ConnectionError < Error; end
  end
end
