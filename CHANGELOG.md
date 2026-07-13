## [Unreleased]

### Fixed

- `find_by` validates field references before formula interpolation — a string key containing
  braces raises `ArgumentError` instead of injecting formula clauses.
- `find` rejects IDs that don't match Airtable's record-ID format with `RecordNotFound` —
  `find(nil)` no longer falls through to the list endpoint and returns a phantom record, and
  IDs are no longer interpolated unvalidated into the URL path.
- `format_formula_value` normalizes `DateTime` values to UTC (they previously matched the
  `Date` branch and kept their local offset) and no longer mutates the caller's `Time` object
  (`getutc` instead of `utc`).
- Formula escaping keeps control characters intact — Airtable formula string literals have no
  escape sequences, so values containing newlines or tabs now actually match.
- The rate limiter prunes its sliding window against the current time (no more spurious ~1 s
  pause on the first request after an idle period) and sleeps outside its mutex, so a throttled
  thread no longer serializes every other thread's request.
- A 2xx response without a records array (e.g. an HTML body from a proxy) raises `ApiError`
  instead of `NoMethodError` deep inside `where`/`count`.
- `preload` and `has_many` readers slice linked-ID lists to the `find_many` per-request cap
  (500), so associations with more links load instead of raising `ArgumentError`.

### Changed

- Invalid `sort:` arguments (anything but a Hash or Array) raise `ArgumentError` instead of
  being silently discarded — `last(sort: :field)` previously ran unsorted and returned an
  arbitrary record.
- A configured table missing from the fetched base schema raises the new
  `Airtable::ORM::ConfigurationError` with a diagnostic message instead of `NoMethodError`
  on `nil`.
- A stale `belongs_to` link to a deleted record reads as `nil` (matching the preloaded path)
  instead of raising `RecordNotFound`.

## [0.1.0] - 2026-07-10

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
