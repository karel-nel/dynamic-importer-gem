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
    has_many :idempotency_records, class_name: "TabularImporter::IdempotencyRecord",
      dependent: :delete_all, inverse_of: :import

    before_validation :assign_idempotency_key, on: :create

    validates :import_type, presence: true
    validates :idempotency_key, presence: true, uniqueness: true
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

    def invalid_rows_count
      value = analysis.to_h["invalid_rows"] || analysis.to_h[:invalid_rows]
      value.to_i
    end

    def has_invalid_rows?
      invalid_rows_count.positive?
    end

    def invalid_source_rows
      values = analysis.to_h["invalid_source_rows"] || analysis.to_h[:invalid_source_rows]
      Array(values).map(&:to_i).select(&:positive?).uniq
    end

    def partial_import_rows_identified?
      !has_invalid_rows? || invalid_source_rows.size == invalid_rows_count
    end

    def idempotency_key_for(scope)
      "#{idempotency_key}:#{scope}"
    end

    def idempotently(scope, &block)
      IdempotencyLedger.call(import: self, key: scope, &block)
    end

    def update_progress!(current:, total:, message: nil, execution_id: nil)
      attributes = {
        progress_current: current.to_i,
        progress_total: total.to_i,
        progress_message: message.to_s,
        updated_at: Time.current
      }
      if execution_id
        attributes[:processor_heartbeat_at] = Time.current
        updated = self.class.where(id:, processor_execution_id: execution_id).update_all(attributes)
        raise ProcessingLeaseUnavailable, "Processor execution lease was lost" if updated.zero?
      else
        update_columns(attributes)
      end
    end

    def transition_to!(next_status, attributes = {})
      next_status = next_status.to_s
      raise InvalidState, "Unknown import state #{next_status.inspect}" unless next_status.in?(STATUSES)

      with_lock do
        update!(attributes.merge(status: next_status))
      end
    end

    def fail!(error, stage: nil)
      attributes = {
        failure_stage: stage,
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(2_000),
        progress_message: "Failed"
      }
      if stage.to_s == "processing"
        attributes[:processor_execution_id] = nil
        attributes[:processor_execution_started_at] = nil
        attributes[:processor_heartbeat_at] = nil
      end
      transition_to!(
        :failed,
        attributes
      )
    end

    def begin_processing!(partial_import_confirmed: false)
      with_lock do
        raise InvalidState, "Only ready imports can be processed" unless status == "ready"
        if has_invalid_rows? && !definition.allow_partial_imports?
          raise InvalidState, "Processing is blocked because the analysis found invalid rows"
        end
        if has_invalid_rows? && !partial_import_confirmed
          raise InvalidState, "Confirm the partial import before processing valid rows"
        end
        if has_invalid_rows? && !partial_import_rows_identified?
          raise InvalidState, "Analysis must report every invalid_source_rows entry before a partial import can run"
        end

        update!(
          status: "processing",
          partial_import_confirmed: has_invalid_rows? && partial_import_confirmed,
          result_summary: {},
          completed_at: nil,
          processor_execution_id: nil,
          processor_execution_started_at: nil,
          processor_heartbeat_at: nil
        )
      end
    end

    def claim_processing!(execution_id)
      with_lock do
        return false if completed?

        heartbeat = processor_heartbeat_at || processor_execution_started_at
        lease_active = processor_execution_id.present? && heartbeat.present? &&
          heartbeat > TabularImporter.configuration.processing_lease_timeout.ago
        return false if lease_active

        retryable_failure = failed? && failure_stage == "processing"
        raise InvalidState, "Import is not available for processing" unless status == "processing" || retryable_failure

        update!(
          status: "processing",
          processor_execution_id: execution_id,
          processor_execution_started_at: Time.current,
          processor_heartbeat_at: Time.current,
          processor_attempts: processor_attempts.to_i + 1,
          started_at: started_at || Time.current,
          error_class: nil,
          error_message: nil
        )
        true
      end
    end

    def complete_processing!(execution_id:, summary:)
      with_lock do
        raise InvalidState, "Processor execution lease was lost" unless processor_execution_id == execution_id
        update!(
          status: "completed",
          result_summary: summary.to_h,
          completed_at: Time.current,
          progress_message: "Import complete",
          failure_stage: nil,
          error_class: nil,
          error_message: nil
        )
      end
    end

    def fail_processing!(execution_id:, error:)
      with_lock do
        return false unless processor_execution_id == execution_id
        update!(
          status: "failed",
          failure_stage: "processing",
          error_class: error.class.name,
          error_message: error.message.to_s.truncate(2_000),
          progress_message: "Failed",
          processor_execution_id: nil,
          processor_execution_started_at: nil,
          processor_heartbeat_at: nil
        )
      end
      true
    end

    def reset_progress!
      update!(progress_current: 0, progress_total: 0, progress_message: nil)
    end

    private

    def assign_idempotency_key
      self.idempotency_key ||= SecureRandom.uuid
    end

    def registered_import_type
      TabularImporter.definition(import_type) if import_type.present?
    rescue UnknownImportType => error
      errors.add(:import_type, error.message)
    end

    def supported_source_file
      return unless source_file.attached?

      extension = source_file.filename.extension.to_s.downcase
      errors.add(:source_file, "must be a CSV or XLSX file") unless extension.in?(%w[csv xlsx])

      allowed_types = TabularImporter.configuration.allowed_content_types.fetch(extension, [])
      content_type = source_file.blob.content_type.to_s.downcase
      unless content_type.in?(allowed_types)
        errors.add(:source_file, "content type does not match a supported #{extension.upcase} upload")
      end

      errors.add(:source_file, "cannot be empty") if source_file.blob.byte_size.zero?

      maximum = TabularImporter.configuration.max_file_size
      if maximum.to_i.positive? && source_file.blob.byte_size > maximum
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
