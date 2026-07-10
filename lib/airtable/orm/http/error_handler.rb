# frozen_string_literal: true

require_relative "../errors"

module Airtable
  module ORM
    module Http
      # Maps the whole Faraday::Error family to Airtable::ORM::ConnectionError so no Faraday type
      # leaks past the client (rationale on the class in error.rb). Safe to catch the base: we don't
      # enable Faraday's :raise_error, so HTTP 4xx/5xx come back as responses (→ Airtable::ORM::ApiError
      # downstream), never raised through here. The original error is kept as #cause.
      class ErrorHandler < Faraday::Middleware
        def call(env)
          @app.call(env)
        rescue Faraday::Error => e
          raise Airtable::ORM::ConnectionError, "Airtable request failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end

Faraday::Request.register_middleware(
  airtable_error_handler: Airtable::ORM::Http::ErrorHandler
)
