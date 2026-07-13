# AI Agent Guidelines — airtable-orm

ActiveModel-style ORM for the Airtable API, extracted from the EUCS Mono Rails app (its
`doc/plans/2026-07-07-airtable-orm-gem-implementation.md` records the extraction). Everything in
this repo is **English-only** — code, comments, docs, fixtures (no Czech strings or diacritics).

## Commands

- `mise install` — Ruby (pinned in `mise.toml`); prefix commands with `mise x --` if the shell
  doesn't activate mise
- `bundle exec rake` — the default task runs specs + RuboCop (both must be green before commit)
- `BUNDLE_GEMFILE=gemfiles/activemodel_7_1.gemfile bundle exec rspec` — the oldest supported
  ActiveModel line (CI runs it on the Rubies Rails 7.1 supports: 3.2/3.3)
- `gem build airtable-orm.gemspec` — must build clean without git (file list uses `Dir.glob`,
  never `git ls-files` — packaging style guide, enforced by rubocop-packaging)

## Load-bearing invariants (break these and consumers break)

- **`ConnectionError` is a deliberate SIBLING of `ApiError`** (both `< Error`), never a subclass:
  `Persistence#save`/`#send_batch_update` rescue `ApiError` into `false`/mark-failed, so a subclass
  would silently swallow outages instead of letting hosts retry. Any new error that must propagate
  stays outside the `ApiError` branch.
- **`lib/airtable/orm/errors.rb` stays loader-ignored** and eagerly required from the entry point —
  Zeitwerk would demand it define `Airtable::ORM::Errors`, and the eager require is what lets host
  class-body macros (`retry_on Airtable::ORM::ConnectionError`) work without any `require`.
  `version.rb` needs NO ignore: `Zeitwerk::GemInflector` special-cases it to `VERSION` (don't
  replace `loader.inflector` wholesale or that mapping is lost).
- **The entry point requires `active_support/core_ext` explicitly** — `require "active_model"`
  transitively loads only blank/class_attribute/delegation; the lib uses `pluck`,
  `deep_symbolize_keys`, `index_by`, `24.hours`, `truncate` which would `NoMethodError` in a
  standalone (non-Rails) host otherwise.
- **Faraday registration keys `:airtable_rate_limiter` / `:airtable_error_handler` are contract** —
  hosts' connection stacks reference them; don't rename.
- **The public API surface is a SemVer contract** — the EUCS Mono app (first consumer) depends on:
  model class methods (`all/where/first/find/find_many/find_by(!)/create(!)/update_many/count/
  field_options/field_schema/field_mapping/format_formula_value/preload`), instance methods
  (`save(!)/update(!)/destroy/reload/url/changed?/persisted?` …), the DSL
  (`attribute/has_many/belongs_to/table_name=`), `Collection`, `BatchResult`, and the full error
  hierarchy. Breaking any of it is a MAJOR bump.
- **`normalizes` is ActiveModel 8.0+ only** — the include in `attributes.rb` is conditional;
  models on 7.1 simply don't have the DSL. Don't make it unconditional (it NameErrors mid-
  `included` block on 7.1 and takes the class_attribute definitions down with it).
- **The gem never reads `Rails.*`, `ENV`, or credentials** — every host touchpoint flows through
  `Airtable::ORM.configure`. Keep it that way; that decoupling was the point of the extraction.

## Airtable API constraints encoded here

- 5 requests/second per base, throttled for 30 s when exceeded → `Http::RateLimiter` (client-side
  sliding window) + `config.rate_limit` default 5 (a hard Airtable limit, not host tuning).
- Batch PATCH takes at most 10 records (`Persistence::BATCH_SIZE`).
- `find_many` builds an OR formula — capped at 500 IDs (`MAX_FIND_MANY_IDS`); associations and
  `preload` slice larger ID lists to the cap (`Associations.fetch_linked_records`).
- `createdTime` is ISO-8601 UTC → parsed with `Time.iso8601` (nil-guarded at both parse sites);
  `Time.zone` doesn't exist outside Rails.
- Record IDs match `\Arec[a-zA-Z0-9_-]+\z` (`Persistence::RECORD_ID_FORMAT`) — validated before
  formula interpolation (`find_many`) and URL-path interpolation (`find`) as an injection guard;
  field references interpolated into `{...}` in formulas must not contain braces (`find_by`).

## Testing conventions

- `spec_helper.rb` wires the fixture config at **load time** (test classes read `ORM.config`
  while spec files load) AND per example via `reset!` + reconfigure — safe here precisely because
  nothing is boot-wired (in a Rails host a global reset would unwire the initializer's config;
  hosts restore inline instead).
- No live HTTP ever: `Testing::StubHelpers` routes through a Faraday test adapter and serves the
  schema from `spec/fixtures/airtable.schema.json`. That fixture is **anonymized** (deterministic
  English placeholder names; real IDs/types/structure) — keep it free of business vocabulary.
- `MemoryCache` decides hit/miss by key presence (false/nil are cacheable — Rails.cache parity)
  and holds one coarse mutex across the fetch block (nested fetches would deadlock — fine for the
  rare schema refresh it serves).
- RuboCop deviations are deliberate and commented in `.rubocop.yml` (multi-constant `errors.rb`,
  the `for_gem_extension` namespace-then-reopen entry point, the dashed require shim, AR-contract
  naming like `has_many`/boolean-returning `save`).

## Releasing

`lib/airtable/orm/version.rb` + `CHANGELOG.md` entry, then `bundle exec rake release` — **from an
interactive terminal**: RubyGems MFA uses a WebAuthn browser flow (a backgrounded push dies with
"execution expired"; `--otp <code>` works non-interactively). `~/.gem/credentials` must be
chmod 0600. If a push errors ambiguously, check https://rubygems.org/gems/airtable-orm before
retrying — an "failed" attempt may have landed server-side. `rubygems_mfa_required` is set in the
gemspec metadata. Follow SemVer against the contract above.
