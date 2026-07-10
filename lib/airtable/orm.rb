# frozen_string_literal: true

require "zeitwerk"
require "active_model"
require "active_support"
# The lib leans broadly on AS core exts standalone (pluck, deep_symbolize_keys, 24.hours,
# truncate…) — active_model's transitive requires load only a tiny subset.
require "active_support/core_ext"
require "faraday"
require "faraday/net_http_persistent"
require "logger"
require "time"

module Airtable; end

loader = Zeitwerk::Loader.for_gem_extension(Airtable)
loader.inflector.inflect("orm" => "ORM")     # orm.rb / orm/ → ORM, not Orm
loader.ignore("#{__dir__}/orm/errors.rb")    # one file, many constants — required eagerly below
loader.ignore("#{__dir__}/orm/testing")      # RSpec-dependent, opt-in via require "airtable/orm/testing"
loader.setup

module Airtable
  module ORM
    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config
      end

      # True when an API key is configured — hosts gate network-touching hooks on this.
      def configured?
        config.api_key.present?
      end

      def reset!
        @config = nil
        Http::Client.reset!
      end
    end
  end
end

require_relative "orm/errors"
