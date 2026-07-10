# frozen_string_literal: true

require_relative "lib/airtable/orm/version"

Gem::Specification.new do |spec|
  spec.name = "airtable-orm"
  spec.version = Airtable::ORM::VERSION
  spec.authors = ["Roman Sklenar"]
  spec.email = ["mail@romansklenar.cz"]

  spec.summary = "ActiveModel-style ORM for the Airtable API"
  spec.description = "CRUD, query DSL, associations, schema introspection, batch updates and " \
                     "rate limiting for Airtable — behind a branded error hierarchy that never " \
                     "leaks the underlying HTTP client."
  spec.homepage = "https://github.com/romansklenar/airtable-orm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Packaging style guide: list files via Dir, never `git ls-files` — downstream
  # (OS packagers, git-less docker builds) must be able to build without git.
  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activemodel", ">= 7.1", "< 9"
  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-net_http_persistent", "~> 2.0"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
