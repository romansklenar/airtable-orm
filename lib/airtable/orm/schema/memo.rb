# frozen_string_literal: true

require "concurrent/atomic/atomic_reference"

module Airtable
  module ORM
    class Schema
      # Per-process memo of ONE base's indexed schema in front of the cache store (Schema keeps
      # one per base_id). Trusted for config.schema_memo_ttl; then one thread reloads while readers
      # with a copy keep reading it and readers without one wait (sharing the result or error).
      # If a reload fails with an API or connection error, the copy keeps serving and the reload
      # is retried after FALLBACK_RETRY.
      class Memo
        Entry = Struct.new(:schema, :expires_at)
        FALLBACK_RETRY = 30 # seconds (capped by the TTL)
        CLEARED = -Float::INFINITY # expires_at of an entry expire!/clear! replaced

        def self.clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def initialize(base_id)
          @base_id = base_id
          @entry = Concurrent::AtomicReference.new # Entry; swapped, never mutated
          @last_failure = nil # [error, failed_at] of the latest reload that had no copy to serve
          @reload_lock = Mutex.new # one reload at a time; held across the load
        end

        # Memoized schema, reloading via the block once the TTL has elapsed.
        def fetch(&)
          return yield unless memoizing?

          entry = @entry.get
          return entry.schema if fresh?(entry)
          # locked? + synchronize rather than try_lock: synchronize keeps lock/unlock paired even
          # under Thread#raise (rack-timeout); losing this racy check only means a brief wait.
          return entry.schema if servable_while_reloading?(entry) && @reload_lock.locked?

          waiting_since = self.class.clock
          @reload_lock.synchronize { reload(waiting_since, &) }
        end

        # Reload via the block now; raises on failure, leaving the previous copy as the fallback.
        def refresh
          return yield unless memoizing?

          @reload_lock.synchronize do
            entry = @entry.get
            store(yield, replacing: entry)
          end
        end

        # Force a reload on next read but keep the copy as the outage fallback. A new entry, so a
        # load in flight (even the first one) sees the change and won't store its result.
        def expire!
          @entry.update { |entry| Entry.new(entry&.schema, CLEARED).freeze }
        end

        # Like expire!, but also drops the fallback copy.
        def clear!
          @entry.set(Entry.new(nil, CLEARED).freeze)
        end

        private

        def reload(waiting_since)
          entry = @entry.get
          return entry.schema if fresh?(entry) # another thread reloaded while we waited

          # The load we queued behind failed with nothing to serve: share its error, don't repeat
          # it (otherwise N cold-start threads would each wait out a timeout in turn).
          error, failed_at = @last_failure
          raise error if failed_at && failed_at > waiting_since

          store(yield, replacing: entry)
        rescue ApiError, ConnectionError => e
          unless entry&.schema
            @last_failure = [e, self.class.clock] unless e.equal?(error)
            raise
          end

          ORM.config.logger.warn("Airtable schema refresh for base #{@base_id} failed, " \
                                 "serving the previous copy: #{e.class}: #{e.message}")
          store(entry.schema, replacing: entry, expires_in: [FALLBACK_RETRY, ttl].min)
        end

        def servable_while_reloading?(entry)
          entry&.schema && entry.expires_at != CLEARED
        end

        def memoizing?
          ttl.positive?
        end

        def fresh?(entry)
          entry && self.class.clock < entry.expires_at
        end

        def ttl
          ORM.config.schema_memo_ttl.to_f # nil → 0.0 (off); a Float compares cheaply
        end

        # Stamped after the load, so the TTL starts once the value is in hand. Only replaces the
        # entry the load started from, so an overtaken load never restores an older copy.
        def store(schema, replacing:, expires_in: ttl)
          @entry.compare_and_set(replacing, Entry.new(schema, self.class.clock + expires_in).freeze)
          schema
        end
      end
    end
  end
end
