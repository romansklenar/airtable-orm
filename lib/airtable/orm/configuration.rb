# frozen_string_literal: true

require "logger"

module Airtable
  module ORM
    # Every host touchpoint is injected here — the gem never reads Rails.*, ENV, or
    # credentials itself. Wired by the host application via Airtable::ORM.configure
    # (in Rails typically from an initializer, inside to_prepare).
    class Configuration
      attr_accessor :api_key, :base_id, :tables, :api_url,
                    :open_timeout, :read_timeout, :rate_limit,
                    :logger, :http_logger, :cache

      def initialize
        @tables = {}
        @api_url = "https://api.airtable.com"
        @open_timeout = 5
        @read_timeout = 10
        @rate_limit = 5                # Airtable throttles for 30 seconds above 5 requests/s per base
        @logger = Logger.new(IO::NULL)
        @http_logger = nil             # set to a Logger to enable Faraday request logging
        @cache = MemoryCache.new       # schema cache default; hosts inject Rails.cache
      end

      # Example: table_fields(:case) => { _id: "id", advisors: "fldgU5KU1qlN8eJ3v", ... }
      def table_fields(table_name)
        tables.dig(table_name.to_sym, :fields)
      end

      # Example: table_id(:case) => "tblQeKH7yYesvWf5p"
      def table_id(table_name)
        tables.dig(table_name.to_sym, :id)
      end

      def table_ids
        tables.values.pluck(:id)
      end

      # Default in-process schema cache so an unconfigured consumer doesn't hit the /v0/meta
      # API on every Schema.fetch (and burn the 5 RPS budget on metadata). Hosts inject a real
      # store (Rails.cache); this one honours only :expires_in. The mutex is held across the
      # fetch block (all keys serialize behind it, and nesting fetch calls would deadlock) —
      # fine for the rare schema refresh this exists for.
      class MemoryCache
        def initialize
          @mutex = Mutex.new
          @store = {}
        end

        def fetch(key, expires_in: nil)
          @mutex.synchronize do
            # Hit/miss by key presence, not value truthiness — false/nil are cacheable
            # (matching Rails.cache semantics).
            if (entry = @store[key])
              value, expires_at = entry
              return value if expires_at.nil? || Time.now < expires_at
            end

            yield.tap { |fresh| @store[key] = [fresh, expires_in && (Time.now + expires_in)] }
          end
        end

        def delete(key)
          @mutex.synchronize { @store.delete(key) }
        end
      end
    end
  end
end
