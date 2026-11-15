# frozen_string_literal: true

require "monitor"

module Airtable
  module ORM
    class Schema
      # Per-process memo of ONE base's indexed schema in front of the cache store (Schema keeps
      # one per base_id). Trusted for config.schema_memo_ttl; then one thread reloads while the
      # others keep reading the previous copy. If a reload fails with an API or connection error,
      # the copy keeps serving and the reload is retried after FALLBACK_RETRY.
      class Memo
        Entry = Struct.new(:schema, :loaded_at)
        FALLBACK_RETRY = 30 # seconds (capped by the TTL)

        def self.clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def initialize(base_id)
          @base_id = base_id
          @entry = nil
          @reload_lock = Monitor.new # one reload at a time; held across the load
          @write_lock = Mutex.new    # short, never held across a load, so expire! never waits
        end

        # Memoized schema, reloading via the block once the TTL has elapsed.
        def fetch(&)
          return yield unless memoizing?

          entry = @entry
          return entry.schema if fresh?(entry)
          return entry.schema if entry&.schema && reloading_elsewhere?

          @reload_lock.synchronize { reload(&) }
        end

        # Reload via the block now; raises on failure, leaving the previous copy as the fallback.
        def refresh(&)
          return yield unless memoizing?

          @reload_lock.synchronize { store(yield, replacing: @entry) }
        end

        # Force a reload on next read but keep the copy as the outage fallback. Always a new entry,
        # so a load in flight (even the first one) sees the change and won't store its result.
        def expire!
          @write_lock.synchronize { @entry = Entry.new(@entry&.schema, -Float::INFINITY).freeze }
        end

        private

        def reload
          entry = @entry
          return entry.schema if fresh?(entry) # another thread reloaded while we waited

          store(yield, replacing: entry)
        rescue ApiError, ConnectionError => e
          raise unless entry&.schema

          ORM.config.logger.warn("Airtable schema refresh for base #{@base_id} failed, " \
                                 "serving the previous copy: #{e.class}: #{e.message}")
          store(entry.schema, replacing: entry, expires_in: [FALLBACK_RETRY, ttl].min)
        end

        def reloading_elsewhere?
          @reload_lock.mon_locked? && !@reload_lock.mon_owned?
        end

        def memoizing?
          ttl.positive?
        end

        def fresh?(entry)
          entry && self.class.clock - entry.loaded_at < ttl
        end

        def ttl
          ORM.config.schema_memo_ttl.to_f # nil → 0.0 (off); a Float compares cheaply
        end

        # Stamped after the load, so the TTL starts once the value is in hand. Only replaces the
        # entry the load started from, so an overtaken load never restores an older copy.
        def store(schema, replacing:, expires_in: ttl)
          loaded_at = self.class.clock - ttl + expires_in
          @write_lock.synchronize { @entry = Entry.new(schema, loaded_at).freeze if @entry.equal?(replacing) }
          schema
        end
      end
    end
  end
end
