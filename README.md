# TabularImporter

`TabularImporter` is a mountable Rails Engine for staged CSV and XLSX imports.
It provides the upload form, sample preview, automatic header matching, column
matcher, analysis confirmation, background processing, progress UI, failures,
and retries. The host application supplies its business-specific analyser and
processor.

## Requirements

- Ruby 3.2 or newer
- Rails 8.0 or newer
- Active Storage
- Any Active Job adapter (Solid Queue, Sidekiq, inline, or async)

The engine has no dependency on Sidekiq, Bootstrap, Stimulus, Turbo, or a
specific authentication library.

## Installation

Add the local gem to the host application's `Gemfile`:

```ruby
gem "tabular_importer", path: "../tabular_importer"
```

Then run:

```sh
bundle install
bin/rails generate tabular_importer:install
bin/rails active_storage:install # only if Active Storage is not installed
bin/rails db:migrate
```

Mount the engine:

```ruby
# config/routes.rb
mount TabularImporter::Engine => "/imports", as: :tabular_importer
```

## Register an import type

Registrations belong in `config/initializers/tabular_importer.rb`. They form a
trusted server-side registry; requests and background-job arguments never
contain service class names.

```ruby
TabularImporter.configure do |config|
  config.authenticate = ->(controller) { controller.send(:authenticate_member!) }
  config.current_actor = ->(controller) { controller.send(:current_member) }

  config.authorize = lambda do |member, import, _action|
    member.present? && import.requester == member
  end

  config.scope = ->(relation, member) { relation.where(requester: member) }
  config.max_file_size = 25.megabytes
  config.preview_rows = 5
  config.max_rows = 100_000
  config.max_columns = 250
  config.max_cell_bytes = 64.kilobytes
  config.max_csv_line_bytes = 1.megabyte
  config.max_xlsx_entries = 10_000
  config.max_xlsx_uncompressed_size = 250.megabytes
  config.max_xlsx_compression_ratio = 100
  config.processing_lease_timeout = 15.minutes

  config.register :event_results,
    title: "Event results",
    description: "Import race results and calculate ranking points.",
    columns: [
      { key: :csa_id, label: "CSA ID", aliases: ["CSA", "CSA identifier"] },
      { key: :id_number, label: "ID number", aliases: ["RSA ID"] },
      { key: :date_of_birth, aliases: ["DOB"] },
      { key: :first_name, aliases: ["Name"] },
      { key: :last_name, aliases: ["Surname"] },
      {
        key: :race_time,
        required: true,
        aliases: ["Time", "Finish time"],
        normalizer: ->(value) { Imports::RaceTime.parse(value) },
        validator: ->(value) { value.to_f.positive? }
      }
    ],
    analyzer: Imports::EventResultsAnalyzer,
    processor: Imports::EventResultsProcessor,
    mapping_validator: Imports::EventResultMappingValidator,
    presenter: Imports::EventResultsPresenter,
    allow_partial_imports: false,
    back_url: ->(controller) { controller.main_app.member_dashboard_path },
    transactional: false
end
```

`back_url` adds a **Back** button to the imports index (for example,
`/member-imports/`). It may be a fixed URL string or a callable receiving the
engine controller, which allows host route helpers to be accessed through
`controller.main_app`. If multiple definitions are registered, the button is
shown only when their resolved, non-empty back URLs are identical. The imports
index does not show a single-definition **New** button; host applications can
link directly to `new_import_path(import_type: ...)`.

Columns accept:

| Option | Meaning |
| --- | --- |
| `key` | Unique normalized row key. |
| `label` | Human-readable label; defaults to the humanized key. |
| `aliases` | Source headers used for automatic matching. Matching ignores case and punctuation. |
| `required` | Requires the column to be mapped and its row value to be present. |
| `normalizer` | Callable or method name applied to every mapped value. |
| `validator` | Callable receiving `value`, or `value, row`; used by the default analyser. |

## Analysis and partial imports

The analyser is optional. Without one, the built-in analyser reports total,
valid, and invalid rows using required columns and column validators. A custom
analyser must return a numeric `invalid_rows` value. Processing is blocked when
that value is greater than zero.

Set `allow_partial_imports: true` on an import definition only when partial
processing is acceptable. A custom analyser must then return both
`invalid_rows` and the complete `invalid_source_rows` array. The engine removes
those exact physical rows from the row stream passed to the processor. The
confirmation screen shows a required checkbox with **Continue Anyway**, plus an
**Upload New File** action that starts a fresh upload for the same import type
and linked domain record. Strict definitions only show the replacement-upload
action. The same processing rules are enforced by the model, so omitting the
checkbox, omitting source row identities, or bypassing the browser cannot start
a partial import.

```ruby
class Imports::EventResultsAnalyzer
  def self.call(import:, rows:, progress:)
    total = rows.count
    existing = 0
    new_records = 0
    invalid_rows = 0
    invalid_source_rows = []

    rows.each.with_index(1) do |(row, source_row), current|
      if row[:race_time].blank?
        invalid_rows += 1
        invalid_source_rows << source_row
      else
        AthleteResolver.call(row) ? existing += 1 : new_records += 1
      end
      progress.call(
        current: current,
        total: total,
        message: "Checking athlete #{current} of #{total}"
      )
    end

    {
      total_rows: total,
      valid_rows: total - invalid_rows,
      invalid_rows: invalid_rows,
      invalid_source_rows: invalid_source_rows,
      existing_athletes: existing,
      new_athletes: new_records
    }
  end
end
```

## Processor contract and idempotency

The processor is required. It receives a fresh, re-readable mapped row set.
The default `transactional: false` allows database-backed progress to remain
visible while work is running. With `transactional: true`, all processor writes
are atomic, but progress updates made inside that database transaction may not
be visible until it commits. For large imports, host processors should normally
use idempotent per-row or per-batch transactions.

```ruby
class Imports::EventResultsProcessor
  def self.call(import:, rows:, progress:)
    event_distance = import.importable
    total = rows.count
    created = 0

    rows.each.with_index(1) do |(row, source_row), current|
      executed = import.idempotently("event-result:source-row:#{source_row}") do
        EventResult.create!(row.merge(distance_id: event_distance.id))
      end
      created += 1 if executed
      progress.call(current: current, total: total, message: "Importing #{current} of #{total}")
    end

    { created: created }
  end
end
```

Both services must return a hash containing JSON-compatible values. The
analyser result appears on the confirmation screen and the processor result on
the completion screen. Exceptions are captured on the import and re-raised so
the configured job adapter can apply its normal retry policy.

Every import receives a persisted UUID `idempotency_key` that remains stable
across manual retries, Active Job retries, and process restarts. Processors must
use a durable idempotency mechanism for every side effect.

For writes in the same database, `import.idempotently(scope) { ... }` creates a
durable, import-scoped ledger entry and executes the block in the same
transaction. A retry with the same scope returns `false` without running the
block again. If the block raises, both its database effects and the ledger entry
roll back so the operation can be retried.

Alternatively, domain tables can persist the import key and source row with a
database unique index:

```ruby
add_column :event_results, :source_import_key, :string, null: false
add_column :event_results, :source_row_number, :integer, null: false
add_index :event_results, %i[source_import_key source_row_number], unique: true
```

For an external API that supports idempotency headers, use a deterministic key:

```ruby
PaymentsClient.create(
  payload,
  idempotency_key: import.idempotency_key_for("source-row:#{source_row}")
)
```

The engine also persists the current Active Job execution ID, attempt count,
start time, and heartbeat. An atomic execution lease suppresses concurrent
duplicate deliveries. A lease can be reclaimed after
`config.processing_lease_timeout`; processors should report progress more
frequently than that timeout. This lease prevents concurrent work, while the
stable idempotency key protects the unavoidable crash window between a domain
write and marking an import complete.

With `transactional: true`, processor writes and the engine's completion state
commit atomically when they share the same database. With
`transactional: false`, database upserts or equivalent idempotent operations
are mandatory. Active Job systems provide at-least-once, not exactly-once,
execution.

## Source-row numbers

`rows` yields `[normalized_row, source_row_number]`. For XLSX, the number is the
actual worksheet row. For CSV, it is the physical starting line of the record,
including blank lines and accounting for quoted records spanning multiple
lines. Blank rows are not yielded, but they still affect later source-row
numbers. This makes analysis errors and idempotency keys point back to the
correct source location.

## Upload and resource limits

Files are checked by extension, declared content type, size, and file
signature. CSV files reject NUL bytes and malformed encoding/quoting. XLSX files
must have a valid ZIP signature and are inspected before Roo parses them to
reject encrypted archives, excessive entry counts, decompression bombs, and
oversized worksheets or cells.

| Setting | Default | Purpose |
| --- | ---: | --- |
| `max_file_size` | `25.megabytes` | Maximum compressed/uploaded file size. |
| `preview_rows` | `5` | Rows retained for the mapping preview. |
| `max_rows` | `100_000` | Maximum data rows or physical XLSX worksheet extent. |
| `max_columns` | `250` | Maximum columns in any source row. |
| `max_cell_bytes` | `64.kilobytes` | Maximum serialized size of one cell. |
| `max_csv_line_bytes` | `1.megabyte` | Maximum bytes in one physical CSV line. |
| `max_xlsx_entries` | `10_000` | Maximum files inside the XLSX ZIP archive. |
| `max_xlsx_uncompressed_size` | `250.megabytes` | Maximum combined uncompressed archive size. |
| `max_xlsx_compression_ratio` | `100` | Maximum compression ratio for any archive entry. |
| `processing_lease_timeout` | `15.minutes` | Time without a processor heartbeat before a claim can be reclaimed. |
| `allowed_content_types` | CSV/XLSX allowlist | Extension-specific MIME allowlist; configurable for trusted upload gateways. |

Setting a numeric resource limit to `0` disables that guard. Do this only after
assessing memory, CPU, request-time, and decompression risks. Preview inspection
scans the source file, so very large allowed imports should be moved behind an
application-level asynchronous upload/preflight workflow.

Complex mapping rules can be supplied separately from row analysis. Return
`true` when valid or an array of error messages:

```ruby
class Imports::EventResultMappingValidator
  def self.call(mapping)
    fields = mapping.values
    identity_present = fields.include?("csa_id") || fields.include?("id_number") ||
      %w[first_name last_name date_of_birth].all? { |key| fields.include?(key) }
    identity_present ? true : ["Map CSA ID, ID number, or name plus date of birth"]
  end
end
```

An optional presenter can provide a processed-results data table. It returns
`columns` plus an array of string- or symbol-keyed `rows`:

```ruby
class Imports::EventResultsPresenter
  def self.call(import:)
    results = import.importable.event_results.order(:finishing_time).limit(10)
    {
      columns: %w[position name race_time points],
      rows: results.map { |result| EventResultSerializer.new(result).as_json }
    }
  end
end
```

## Linking an import to a domain record

Use a purpose-bound Signed Global ID instead of accepting model names and IDs
from request parameters:

```erb
<%= link_to "Upload results",
  tabular_importer.new_import_path(
    import_type: :event_results,
    importable_sgid: distance.to_sgid(expires_in: 2.hours, for: "tabular_importer")
  ) %>
```

The processor can then access `import.importable`. The uploader is stored as
the polymorphic `import.requester`. Polymorphic IDs are stored as strings so
both UUID- and bigint-keyed host models are supported.

## Lifecycle callbacks

```ruby
config.after_complete = ->(import) { ImportMailer.completed(import).deliver_later }
config.after_failure = ->(import, error) { ErrorTracker.notify(error, import_id: import.id) }
```

Callback failures are logged and do not change a successfully completed
import back to failed.

## Security

- The default authorization policy denies access unless the current actor owns
  the import. Configure authentication, actor, authorization, and scope hooks.
- Import contexts use expiring Signed Global IDs.
- Mapping is validated on the server; the browser checks are only usability aids.
- Processing uses POST and mapping uses PATCH.
- File extension and size are validated before previewing.
- File signatures, MIME types, row/column/cell limits, and XLSX archive
  expansion limits are enforced before analysis.
- Imports with invalid rows cannot be processed unless partial imports are
  enabled by the trusted definition and explicitly confirmed by the user.
- Processor execution claims and stable idempotency keys protect retries and
  duplicate job delivery.
- Job progress is stored on the authorized import record and has no public
  Sidekiq-status endpoint.

## Development

```sh
bundle install
bundle exec rake test
bundle exec rake build
```

The test application uses an in-memory SQLite database and the Active Job test
adapter.
