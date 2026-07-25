module TabularImporter
  class Import < ApplicationRecord
    self.table_name = "tabular_importer_imports"

    STATUSES = %w[
      uploaded mapping_required analyzing ready processing completed failed cancelled
    ].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    belongs_to :requester, polymorphic: true, optional: true
    belongs_to :importable, polymorphic: true, optional: true

    has_one_attached :source_file

    validates :import_type, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :source_file, presence: true, on: :create
    validate :registered_import_type
    validate :supported_source_file
    validate :valid_metadata

    scope :recent_first, -> { order(created_at: :desc) }

    def definition
      TabularImporter.definition(import_type)
    end

    def terminal?
      status.in?(TERMINAL_STATUSES)
    end

    def failed?
      status == "failed"
    end

    def completed?
      status == "completed"
    end

    def update_progress!(current:, total:, message: nil)
      update_columns(
        progress_current: current.to_i,
        progress_total: total.to_i,
        progress_message: message.to_s,
        updated_at: Time.current
      )
    end

    def transition_to!(next_status, attributes = {})
      next_status = next_status.to_s
      raise InvalidState, "Unknown import state #{next_status.inspect}" unless next_status.in?(STATUSES)

      with_lock do
        update!(attributes.merge(status: next_status))
      end
    end

    def fail!(error, stage: nil)
      transition_to!(
        :failed,
        failure_stage: stage,
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(2_000),
        progress_message: "Failed"
      )
    end

    def reset_progress!
      update!(progress_current: 0, progress_total: 0, progress_message: nil)
    end

    private

    def registered_import_type
      TabularImporter.definition(import_type) if import_type.present?
    rescue UnknownImportType => error
      errors.add(:import_type, error.message)
    end

    def supported_source_file
      return unless source_file.attached?

      extension = source_file.filename.extension.to_s.downcase
      errors.add(:source_file, "must be a CSV or XLSX file") unless extension.in?(%w[csv xlsx])

      maximum = TabularImporter.configuration.max_file_size
      if source_file.blob.byte_size > maximum
        errors.add(:source_file, "must be smaller than #{ActiveSupport::NumberHelper.number_to_human_size(maximum)}")
      end
    end

    def valid_metadata
      validator = definition.metadata_validator
      return unless validator
      result = validator.call(metadata.to_h)
      return if result == true
      messages = Array(result).compact
      (messages.presence || ["is invalid"]).each { |message| errors.add(:metadata, message) }
    rescue UnknownImportType
      nil
    end
  end
end
