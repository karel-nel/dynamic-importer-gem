module TabularImporter
  class IdempotencyRecord < ApplicationRecord
    self.table_name = "tabular_importer_idempotency_records"

    belongs_to :import, class_name: "TabularImporter::Import", inverse_of: :idempotency_records

    validates :key, presence: true, length: { maximum: 500 }, uniqueness: { scope: :import_id }
  end
end
