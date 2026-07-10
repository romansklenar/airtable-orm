# frozen_string_literal: true

module Airtable
  module ORM
    class Schema
      CACHE_KEY = "airtable:schema"
      CACHE_EXPIRY = 24.hours

      class << self
        def fetch(base_id, force_refresh: false)
          clear_cache(base_id) if force_refresh

          cache.fetch(cache_key(base_id), expires_in: CACHE_EXPIRY) { fetch_from_api(base_id) }
        end

        def clear_cache(base_id)
          cache.delete(cache_key(base_id))
        end

        private

        def required_table_ids
          ORM.config.table_ids
        end

        def fetch_from_api(base_id)
          response = client.connection.get("/v0/meta/bases/#{base_id}/tables")
          parsed_response = response.body

          if response.success?
            indexed_schema(parsed_response)
          else
            Http::Client.raise_api_error(response.status, parsed_response)
          end
        end

        def indexed_schema(parsed_response)
          tables = parsed_response.deep_symbolize_keys[:tables]

          # Filter only required tables
          tables.select! { |table| required_table_ids.include?(table[:id]) }

          # Transform fields into hash indexed by field id
          tables.each do |table|
            table[:fields] = table[:fields].index_by { |field| field[:id] }
          end

          # Index tables by table id
          tables.index_by { |table| table[:id] }
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
