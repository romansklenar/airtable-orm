# frozen_string_literal: true

module Airtable
  module ORM
    module Http
      class RateLimiter < Faraday::Middleware
        def initialize(app, requests_per_second: nil, sleeper: nil)
          super(app)
          @rps = requests_per_second
          @sleeper = sleeper || ->(seconds) { sleep(seconds) }
          @mutex = Mutex.new
          @requests = []
        end

        def call(env)
          throttle if @rps
          @app.call(env)
        end

        def clear
          @mutex.synchronize { @requests = [] }
        end

        private

        # Compute the wait under the lock but sleep outside it, so a throttled thread
        # doesn't serialize every other thread's request behind its sleep.
        def throttle
          wait_time = @mutex.synchronize do
            now = monotonic_now
            prune(now)
            1.0 - (now - @requests.first) if @requests.size >= @rps
          end

          @sleeper.call(wait_time) if wait_time&.positive?

          @mutex.synchronize do
            now = monotonic_now
            prune(now)
            @requests << now
            @requests.shift while @requests.size > @rps
          end
        end

        # Drop timestamps that fell out of the 1-second sliding window — without this,
        # a full window recorded before an idle period would throttle the next request.
        def prune(now)
          @requests.shift while @requests.any? && now - @requests.first >= 1.0
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end

Faraday::Request.register_middleware(
  airtable_rate_limiter: Airtable::ORM::Http::RateLimiter
)
