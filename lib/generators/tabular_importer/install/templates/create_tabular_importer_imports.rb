class CreateTabularImporterImports < ActiveRecord::Migration[8.0]
  def change
    create_table :tabular_importer_imports do |t|
      t.string :import_type, null: false
      t.string :status, null: false, default: "uploaded"
      t.string :idempotency_key, null: false
      # String polymorphic IDs support hosts using either bigint or UUID keys.
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

    add_index :tabular_importer_imports, [:import_type, :status]
    add_index :tabular_importer_imports, :idempotency_key, unique: true
    add_index :tabular_importer_imports, [:requester_type, :requester_id]
    add_index :tabular_importer_imports, [:importable_type, :importable_id]
    add_index :tabular_importer_imports, :created_at

    create_table :tabular_importer_idempotency_records do |t|
      # String IDs keep this ledger compatible with bigint and UUID import keys.
      t.string :import_id, null: false
      t.string :key, null: false, limit: 500
      t.timestamps
    end
    add_index :tabular_importer_idempotency_records, [:import_id, :key],
      unique: true, name: "index_tabular_importer_idempotency_records_unique"
  end
end
