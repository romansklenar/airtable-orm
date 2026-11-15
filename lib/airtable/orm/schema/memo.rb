# frozen_string_literal: true

module Airtable
  module ORM
    class Schema
      # Per-process memo of ONE base's indexed schema in front of the cache store (Schema keeps
      # one per base_id). Trusted for config.schema_memo_ttl; after that the next read reloads.
      # If a reload fails with an API or connection error, the previous copy keeps serving for
      # another TTL. Readers never lock; writes take a short mutex and only replace the entry
      # they started from, so a slow or failed reload never restores an older copy.
      class Memo
        Entry = Struct.new(:schema, :loaded_at)

        def self.clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def initialize(base_id)
          @base_id = base_id
          @mutex = Mutex.new
          @entry = nil
        end

        # Memoized schema, reloading via the block once the TTL has elapsed.
        def fetch
          return yield unless memoizing?

          entry = @entry
          return entry.schema if fresh?(entry)

          store(yield, replacing: entry)
        rescue ApiError, ConnectionError => e
          raise unless entry&.schema

          ORM.config.logger.warn("Airtable schema refresh for base #{@base_id} failed, " \
                                 "serving the previous copy: #{e.class}: #{e.message}")
          store(entry.schema, replacing: entry)
        end

        # Reload via the block now; raises on failure, leaving the previous copy as the fallback.
        def refresh
          entry = @entry
          memoizing? ? store(yield, replacing: entry) : yield
        end

        # Force a reload on next read but keep the copy as the outage fallback. Always a new entry,
        # so a load in flight (even the first one) sees the change and won't store its result.
        def expire!
          @mutex.synchronize { @entry = Entry.new(@entry&.schema, -Float::INFINITY).freeze }
        end

        # Forget everything, including the fallback copy.
        def clear!
          @mutex.synchronize { @entry = nil }
        end

        private

        def memoizing?
          ttl.positive?
        end

        def fresh?(entry)
          entry && self.class.clock - entry.loaded_at < ttl
        end

        def ttl
          ORM.config.schema_memo_ttl.to_f # nil → 0.0 (off); a Float compares cheaply
        end

        # Stamped after the load, so the TTL starts once the value is in hand.
        def store(schema, replacing:)
          @mutex.synchronize do
            @entry = Entry.new(schema, self.class.clock).freeze if @entry.equal?(replacing)
          end
          schema
        end
      end
    end
  end
end
