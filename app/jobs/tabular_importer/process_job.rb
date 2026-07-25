module TabularImporter
  class ProcessJob < ApplicationJob
    queue_as :default
    retry_on ProcessingLeaseUnavailable, wait: 30.seconds, attempts: 50

    def perform(import)
      execution_id = job_id
      unless import.claim_processing!(execution_id)
        return if import.reload.completed?
        raise ProcessingLeaseUnavailable, "Another processor currently holds this import's execution lease"
      end

      excluded_rows = import.partial_import_confirmed? ? import.invalid_source_rows : []
      rows = MappedRows.new(import, excluded_source_rows: excluded_rows)
      progress = ProgressReporter.new(import, total: rows.count, execution_id:)

      operation = lambda do |_transaction = nil|
        summary = import.definition.processor.call(import:, rows:, progress:).to_h
        progress.finish("Import complete")
        import.complete_processing!(execution_id:, summary:)
        summary
      end

      if import.definition.transactional?
        ActiveRecord::Base.transaction(requires_new: true, &operation)
      else
        operation.call
      end

      run_completion_callback(import)
    rescue StandardError => error
      handle_failure(import, error, execution_id)
      raise
    end

    private

    def run_completion_callback(import)
      TabularImporter.configuration.after_complete.call(import)
    rescue StandardError => error
      Rails.logger.error("TabularImporter completion callback failed: #{error.message}")
    end

    def handle_failure(import, error, execution_id)
      failed = !import.destroyed? && import.fail_processing!(execution_id:, error:)
      TabularImporter.configuration.after_failure.call(import, error) if failed
    rescue StandardError => callback_error
      Rails.logger.error("TabularImporter failure callback failed: #{callback_error.message}")
    end
  end
end
