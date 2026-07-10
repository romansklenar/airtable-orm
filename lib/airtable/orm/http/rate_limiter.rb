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
          @mutex.synchronize do
            wait if too_many_requests_in_last_second?
            @requests << Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @requests.shift if @rps && @requests.size > @rps
          end
          @app.call(env)
        end

        def clear
          @mutex.synchronize { @requests = [] }
        end

        private

        def too_many_requests_in_last_second?
          return false unless @rps
          return false unless @requests.size >= @rps

          window_span < 1.0
        end

        def wait
          wait_time = 1.0 - window_span
          @sleeper.call(wait_time)
        end

        def window_span
          @requests.last - @requests.first
        end
      end
    end
  end
end

Faraday::Request.register_middleware(
  airtable_rate_limiter: Airtable::ORM::Http::RateLimiter
)
