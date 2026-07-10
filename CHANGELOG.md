## [Unreleased]

## [0.1.0] - unreleased

Initial release — the generic Airtable client/ORM extracted from the EUCS Mono application:

- `Airtable::ORM::Base` with the attribute DSL, querying (formula building, automatic pagination),
  persistence (incl. `update_many` batching with `BatchResult`), associations with preloading,
  and schema introspection cached via the injected store.
- Host-agnostic configuration through `Airtable::ORM.configure` (API key, base/table/field IDs,
  timeouts, rate limit, loggers, schema cache — in-process `MemoryCache` by default).
- Branded error hierarchy (`ApiError`, its deliberate sibling `ConnectionError`, ActiveRecord-style
  record errors) — the underlying HTTP client never leaks to consumers.
- Client-side rate limiting (5 requests/s per base) and fail-fast timeouts on a persistent
  Faraday connection.
- Opt-in RSpec test support (`airtable/orm/testing`): Faraday test adapter wiring and
  schema-fixture stubbing.
