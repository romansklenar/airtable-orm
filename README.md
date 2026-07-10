# Airtable::ORM

An ActiveModel-style ORM for the [Airtable API](https://airtable.com/developers/web/api/introduction): CRUD, a query DSL with formula building, associations with preloading, schema introspection, batch updates and client-side rate limiting — behind a branded error hierarchy that never leaks the underlying HTTP client.

```ruby
class Order < Airtable::ORM::Base
  self.table_name = :order

  attribute :email, :string
  attribute :state, :string

  belongs_to :client, class_name: "Client", foreign_key: :client_ids
end

Order.where(formula: "AND({Stav} = 'Aktivní')").each { |order| puts order.email }
Order.find_by(email: "jane@example.com")&.update(state: "Uzavřený")
```

## Installation

```ruby
# Gemfile
gem "airtable-orm"
```

## Configuration

The gem never reads `Rails.*`, `ENV`, or credentials itself — every host touchpoint is injected:

```ruby
# e.g. config/initializers/airtable.rb in a Rails app
Airtable::ORM.configure do |config|
  config.api_key      = Rails.application.credentials.dig(:airtable, :api_key)
  config.base_id      = "appXXXXXXXXXXXXXX"
  config.tables       = {
    order: {
      id: "tblXXXXXXXXXXXXXX",
      fields: { _id: "id", email: "fldXXXXXXXXXXXXXX", state: "fldYYYYYYYYYYYYYY" }
    }
  }
  config.cache        = Rails.cache    # schema cache; defaults to an in-process MemoryCache
  config.logger       = Rails.logger   # defaults to a null logger
end
```

| Option | Default | Purpose |
| --- | --- | --- |
| `api_key` | — (required) | Airtable personal access token |
| `base_id` | — (required) | The base your models live in |
| `tables` | `{}` | `table_name => { id:, fields: { attribute => field_id } }` map |
| `api_url` | `https://api.airtable.com` | API endpoint |
| `open_timeout` / `read_timeout` | `5` / `10` seconds | Fail fast instead of hanging a worker |
| `rate_limit` | `5` | Requests/second per base (Airtable throttles for 30 s above 5) |
| `logger` | null logger | Batch-update failure reporting |
| `http_logger` | `nil` | Set to a `Logger` to log Faraday requests |
| `cache` | in-process `MemoryCache` | Schema cache; anything responding to `fetch`/`delete` |

`Airtable::ORM.configured?` returns whether an `api_key` is set — handy for gating enqueue hooks so test/CI environments never touch the network.

## Models

```ruby
class Case < Airtable::ORM::Base
  self.table_name = :case               # key into config.tables

  attribute :label, :string
  attribute :potential, :big_integer
  attribute :tags, :airtable_array      # multipleSelects / multipleRecordLinks
  attribute :client_ids, :airtable_array

  has_many :clients, class_name: "Client", foreign_key: :client_ids
end
```

- **Querying:** `all`, `where(formula:, sort:, max_records:)`, `first`, `find`, `find_many`, `find_by`/`find_by!`, `count`. Symbol conditions build (and escape) Airtable formulas; pagination is automatic.
- **Persistence:** `save`/`save!`, `create`/`create!`, `update`/`update!`, `destroy`, `reload`, plus `Model.update_many(records)` batching 10 per PATCH with a `BatchResult` (`updated`/`skipped`/`failed`).
- **Associations:** `has_many`/`belongs_to` readers, writers, `add_*`/`remove_*`, memoization and `Collection#preload` for eager loading.
- **Schema:** table/field metadata from `/v0/meta/bases`, cached via `config.cache`; `Model.field_options(:state)` reads select options.
- **`#url`** — deeplink to the record in the Airtable UI.
- **`normalizes`** — available on ActiveModel 8.0+ (the DSL doesn't exist in 7.1).

## Errors

Consumers rescue `Airtable::ORM::*` only — the HTTP client (Faraday today) never leaks, so swapping transports is not a breaking change.

| Error | Raised when |
| --- | --- |
| `Airtable::ORM::ApiError` | Airtable answered with an error (rate limit, 5xx, validation) |
| `Airtable::ORM::ConnectionError` | The request never completed (timeout, DNS, TLS) — a **sibling** of `ApiError`, so `save`'s `rescue ApiError => false` never swallows an outage |
| `Airtable::ORM::RecordNotFound` / `RecordInvalid` / `RecordNotSaved` / `RecordNotDestroyed` / `RecordNotPersisted` | ActiveRecord-style persistence failures |
| `Airtable::ORM::UnknownFieldError` / `InvalidAttributeError` | Mapping problems |

All error classes are defined eagerly at require time, so `retry_on Airtable::ORM::ConnectionError` in a class body needs no extra `require`.

## Test support

```ruby
# spec_helper.rb
require "airtable/orm/testing"

Airtable::ORM::Testing.schema_fixture_path = "spec/fixtures/airtable.schema.json"

RSpec.configure do |config|
  config.include Airtable::ORM::Testing::StubHelpers, :airtable
  config.before(:each, :airtable) { stub_airtable_http_client }
end
```

`stub_airtable_http_client` routes every request through a Faraday test adapter (returned for stubbing) and serves schema lookups from your fixture — no HTTP leaves the process.

## Development

`mise install` (or any Ruby ≥ 3.2), `bin/setup`, then `bundle exec rake` (specs + RuboCop). Release: bump `lib/airtable/orm/version.rb`, update `CHANGELOG.md`, `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome at <https://github.com/romansklenar/airtable-orm>.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
