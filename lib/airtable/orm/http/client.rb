# frozen_string_literal: true

require_relative "rate_limiter"
require_relative "error_handler"

module Airtable
  module ORM
    module Http
      class Client
        attr_reader :api_key

        # Shared client instance with credential validation.
        # Used by Persistence and Schema to avoid duplicating client/key setup.
        def self.default
          @default ||= begin
            key = ORM.config.api_key
            if key.blank?
              raise Airtable::ORM::Error,
                    "Airtable API key is missing. Set api_key via Airtable::ORM.configure."
            end

            new(key)
          end
        end

        def self.reset!
          @default = nil
        end

        def initialize(api_key)
          @api_key = api_key
        end

        def connection
          @connection ||= Faraday.new(url: api_uri, headers: headers) do |builder|
            builder.options.open_timeout = ORM.config.open_timeout
            builder.options.timeout = ORM.config.read_timeout
            # Outermost middleware so its rescue wraps every inner handler and the adapter — maps raw
            # Faraday transport errors to Airtable::ORM::ConnectionError before they leave the client.
            builder.request :airtable_error_handler
            builder.request :json
            builder.request :airtable_rate_limiter, requests_per_second: ORM.config.rate_limit
            builder.response :json
            builder.adapter :net_http_persistent

            if (http_logger = ORM.config.http_logger)
              builder.response :logger, http_logger, bodies: { request: true, response: false }, headers: false,
                                                     errors: true, log_level: :debug
            end
          end
        end

        def api_uri
          @api_uri ||= URI.parse(ORM.config.api_url)
        end

        def headers
          {
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json",
            "User-Agent" => "airtable-orm/#{VERSION}"
          }
        end

        def escape(string)
          ERB::Util.url_encode(string)
        end

        # Parse an Airtable API error response and raise an ApiError.
        def self.raise_api_error(status, error)
          type = (error.is_a?(Hash) && error.dig("error", "type")) || "Communication error"
          msg = case error
                when Hash then error.dig("error", "message")
                when String then error
                when NilClass then "invalid or empty response body (not valid JSON)"
                else error.inspect
                end

          raise Airtable::ORM::ApiError.new("HTTP #{status}: #{type}: #{msg.to_s.truncate(200, omission: "…")}",
                                            status: status, response: error)
        end
      end
    end
  end
end
