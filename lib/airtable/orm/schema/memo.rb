# frozen_string_literal: true

module Airtable
  module ORM
    class Schema
      # Per-process memo of ONE base's indexed schema in front of the cache store (Schema keeps
      # one per base_id), trusted for config.schema_memo_ttl. If a reload fails with an API or
      # connection error, the previous copy keeps serving and the reload is retried after
      # FALLBACK_RETRY. No locking: concurrent reloads just re-read the store, and the last write
      # wins (entries are frozen, an ivar write is atomic).
      class Memo
        Entry = Struct.new(:schema, :expires_at)
        FALLBACK_RETRY = 30 # seconds (capped by the TTL)

        def self.clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def initialize(base_id)
          @base_id = base_id
          @entry = nil
        end

        # Memoized schema, reloading via the block once the TTL has elapsed.
        def fetch
          return yield unless memoizing?

          entry = @entry
          return entry.schema if entry && self.class.clock < entry.expires_at

          store(yield, ttl)
        rescue ApiError, ConnectionError => e
          raise unless entry&.schema

          ORM.config.logger.warn("Airtable schema refresh for base #{@base_id} failed, " \
                                 "serving the previous copy: #{e.class}: #{e.message}")
          store(entry.schema, [FALLBACK_RETRY, ttl].min)
        end

        # Reload via the block now; raises on failure, leaving the previous copy as the fallback.
        def refresh
          memoizing? ? store(yield, ttl) : yield
        end

        # Force a reload on next read but keep the copy as the outage fallback.
        def expire!
          entry = @entry
          @entry = Entry.new(entry.schema, -Float::INFINITY).freeze if entry
        end

        private

        def memoizing?
          ttl.positive?
        end

        def ttl
          ORM.config.schema_memo_ttl.to_f # nil → 0.0 (off)
        end

        # Stamped after the load, so the TTL starts once the value is in hand.
        def store(schema, expires_in)
          @entry = Entry.new(schema, self.class.clock + expires_in).freeze
          schema
        end
      end
    end
  end
end
