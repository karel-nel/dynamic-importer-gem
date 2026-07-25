ENV["RAILS_ENV"] = "test"

require "bundler/setup"
require "logger"
require "tmpdir"
require "rails"
require "active_record/railtie"
require "active_storage/engine"
require "active_job/railtie"
require "action_controller/railtie"
require "tabular_importer"

class TabularImporterTestApplication < Rails::Application
  config.root = __dir__
  config.eager_load = false
  config.secret_key_base = "tabular-importer-test-secret-key-base"
  config.logger = Logger.new(nil)
  config.hosts << "www.example.com"
  config.action_controller.allow_forgery_protection = false
  config.active_job.queue_adapter = :test
  config.active_storage.service = :test
  config.active_storage.service_configurations = {
    test: { service: "Disk", root: File.join(Dir.tmpdir, "tabular-importer-storage") }
  }

  routes.append do
    mount TabularImporter::Engine => "/imports", as: :tabular_importer
  end
end

TabularImporterTestApplication.initialize!

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :tabular_importer_imports do |t|
    t.string :import_type, null: false
    t.string :status, null: false, default: "uploaded"
    t.string :idempotency_key, null: false
    t.string :requester_type
    t.string :requester_id
    t.string :importable_type
    t.string :importable_id
    t.json :metadata, null: false, default: {}
    t.json :source_headers, null: false, default: []
    t.json :preview_rows, null: false, default: []
    t.json :column_mapping, null: false, default: {}
    t.json :analysis, null: false, default: {}
    t.json :result_summary, null: false, default: {}
    t.integer :progress_current, null: false, default: 0
    t.integer :progress_total, null: false, default: 0
    t.string :progress_message
    t.string :failure_stage
    t.string :error_class
    t.text :error_message
    t.datetime :started_at
    t.datetime :completed_at
    t.boolean :partial_import_confirmed, null: false, default: false
    t.string :processor_execution_id
    t.integer :processor_attempts, null: false, default: 0
    t.datetime :processor_execution_started_at
    t.datetime :processor_heartbeat_at
    t.integer :lock_version, null: false, default: 0
    t.timestamps
  end
  add_index :tabular_importer_imports, :idempotency_key, unique: true

  create_table :tabular_importer_idempotency_records do |t|
    t.string :import_id, null: false
    t.string :key, null: false, limit: 500
    t.timestamps
  end
  add_index :tabular_importer_idempotency_records, [:import_id, :key], unique: true,
    name: "index_tabular_importer_idempotency_records_unique"

  create_table :active_storage_blobs do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
    t.index :key, unique: true
  end

  create_table :active_storage_attachments do |t|
    t.string :name, null: false
    t.references :record, null: false, polymorphic: true
    t.references :blob, null: false
    t.datetime :created_at, null: false
    t.index [:record_type, :record_id, :name, :blob_id], unique: true, name: :active_storage_attachments_uniqueness
  end

  create_table :test_actors do |t|
    t.string :name
    t.timestamps
  end

  create_table :processed_rows do |t|
    t.string :external_id
    t.string :name
    t.timestamps
  end
end

class TestActor < ActiveRecord::Base
end

class ProcessedRow < ActiveRecord::Base
end

class TestProcessor
  def self.call(import:, rows:, progress:)
    total = rows.count
    created = 0
    rows.each.with_index(1) do |(row, source_row), current|
      executed = import.idempotently("source-row:#{source_row}") do
        ProcessedRow.create!(external_id: row[:external_id], name: row[:name])
      end
      created += 1 if executed
      progress.call(current:, total:, message: "Processing #{current}")
    end
    { created: }
  end
end

require "minitest/autorun"
require "active_job/test_helper"

class ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    TabularImporter.reset_configuration!
    TabularImporter.register :people,
      title: "People",
      columns: [
        { key: :external_id, required: true, aliases: ["CSA ID", "ID"] },
        { key: :name, required: true, aliases: ["First Name"] },
        { key: :last_name, aliases: ["Surname", "Last Name"] },
        { key: :race_time, aliases: ["Race Time"] }
      ],
      processor: TestProcessor

    ProcessedRow.delete_all
    TabularImporter::IdempotencyRecord.delete_all
    TabularImporter::Import.delete_all
    ActiveStorage::Attachment.delete_all
    ActiveStorage::Blob.delete_all
    clear_enqueued_jobs
    clear_performed_jobs
  end

  def build_import(filename: "results.csv", import_type: "people", content_type: nil)
    import = TabularImporter::Import.new(import_type:)
    path = File.join(__dir__, "fixtures", "files", filename)
    content_type ||= filename.end_with?(".xlsx") ?
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" : "text/csv"
    import.source_file.attach(io: File.open(path), filename:, content_type:)
    import.save!
    import.reload
  end
end
