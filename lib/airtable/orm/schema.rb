# frozen_string_literal: true

module Airtable
  module ORM
    class Schema
      CACHE_KEY = "airtable:schema"
      # Deprecated — superseded by config.schema_cache_expiry (same 24h default); no longer read.
      CACHE_EXPIRY = 24.hours
      # When an entry expires, ActiveSupport stores keep serving the stale value this long to
      # other readers while one process refetches, so expiry doesn't stampede /v0/meta.
      RACE_CONDITION_TTL = 30.seconds

      class << self
        def fetch(base_id, force_refresh: false)
          clear_cache(base_id) if force_refresh

          cache.fetch(cache_key(base_id), **cache_options) { fetch_from_api(base_id) }
        end

        def clear_cache(base_id)
          cache.delete(cache_key(base_id))
        end

        private

        def fetch_from_api(base_id)
          response = client.connection.get("/v0/meta/bases/#{base_id}/tables")
          parsed_response = response.body

          if response.success?
            indexed_schema(parsed_response)
          else
            Http::Client.raise_api_error(response.status, parsed_response)
          end
        end

        # Index the FULL base schema — no filtering by the tables configured at fetch time.
        # The cached payload outlives the config (config.schema_cache_expiry, a shared store in
        # Rails hosts), so a fetch-time filter would hide tables added to config after the cache
        # warmed up.
        # Reads are keyed lookups (fetch(base_id)[table_id]), so no read-time filter is needed.
        def indexed_schema(parsed_response)
          tables = parsed_response.deep_symbolize_keys[:tables]

          # Transform fields into hash indexed by field id
          tables.each do |table|
            table[:fields] = table[:fields].index_by { |field| field[:id] }
          end

          # Index tables by table id
          tables.index_by { |table| table[:id] }
        end

        # Only ActiveSupport stores understand :race_condition_ttl — the built-in MemoryCache
        # (and any minimal host store) accepts just :expires_in. While ActiveSupport::Cache is
        # still an unloaded autoload the store can't be one of its subclasses, so the check
        # doesn't load the cache library into a standalone host.
        def cache_options
          options = { expires_in: ORM.config.schema_cache_expiry }
          options[:race_condition_ttl] = RACE_CONDITION_TTL if active_support_store?
          options
        end

        def active_support_store?
          !ActiveSupport.autoload?(:Cache) && cache.is_a?(ActiveSupport::Cache::Store)
        end

        def cache_key(base_id)
          "#{CACHE_KEY}:#{base_id}"
        end

        def cache
          ORM.config.cache
        end

        def client
          Http::Client.default
        end
      end
    end
  end
end
