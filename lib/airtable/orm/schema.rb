# frozen_string_literal: true

require "concurrent/map"

module Airtable
  module ORM
    class Schema
      CACHE_KEY = "airtable:schema"
      # Superseded by config.schema_cache_expiry; no longer read.
      CACHE_EXPIRY = 24.hours
      deprecate_constant :CACHE_EXPIRY

      MEMOS = Concurrent::Map.new # base_id → Memo
      private_constant :MEMOS

      class << self
        # Indexed base schema: the per-process memo (config.schema_memo_ttl), then the cache store
        # (config.schema_cache_expiry), then /v0/meta. force_refresh clears both and refetches; it
        # raises on failure, while the memo keeps its copy as the outage fallback.
        def fetch(base_id, force_refresh: false)
          base_id = base_id.to_s
          memo = memo_for(base_id)
          return memo.fetch { read_store(base_id) } unless force_refresh

          clear_cache(base_id)
          memo.refresh { read_store(base_id) }
        end

        # Deletes the store entry and expires this process's memo (it keeps its copy as the outage
        # fallback); with a shared store, other processes follow once their schema_memo_ttl elapses.
        def clear_cache(base_id)
          cache.delete(cache_key(base_id)).tap { MEMOS[base_id.to_s]&.expire! }
        end

        # Drops this process's memo for the base, fallback copy included.
        def clear_memo(base_id)
          MEMOS[base_id.to_s]&.clear!
          nil
        end

        # Drops every memo in this process (ORM.configure and ORM.reset!).
        def reset_memos!
          MEMOS.clear
        end

        private

        def memo_for(base_id)
          MEMOS.compute_if_absent(base_id) { Memo.new(base_id) }
        end

        def read_store(base_id)
          cache.fetch(cache_key(base_id), expires_in: ORM.config.schema_cache_expiry) do
            fetch_from_api(base_id)
          end
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
