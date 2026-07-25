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
    transactional: false
end
```

Columns accept:

| Option | Meaning |
| --- | --- |
| `key` | Unique normalized row key. |
| `label` | Human-readable label; defaults to the humanized key. |
| `aliases` | Source headers used for automatic matching. Matching ignores case and punctuation. |
| `required` | Requires the column to be mapped and its row value to be present. |
| `normalizer` | Callable or method name applied to every mapped value. |
| `validator` | Callable receiving `value`, or `value, row`; used by the default analyser. |

## Service contracts

The analyser is optional. Without one, the built-in analyser reports total,
valid, and invalid rows using required columns and column validators.

```ruby
class Imports::EventResultsAnalyzer
  def self.call(import:, rows:, progress:)
    total = rows.count
    existing = 0
    new_records = 0

    rows.each.with_index(1) do |(row, _source_row), current|
      AthleteResolver.call(row) ? existing += 1 : new_records += 1
      progress.call(
        current: current,
        total: total,
        message: "Checking athlete #{current} of #{total}"
      )
    end

    { total_rows: total, existing_athletes: existing, new_athletes: new_records }
  end
end
```

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

    rows.each.with_index(1) do |(row, _source_row), current|
      EventResults::Create.call(distance: event_distance, attributes: row)
      created += 1
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

Processors should be idempotent because every background system provides
at-least-once, rather than exactly-once, execution.

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
