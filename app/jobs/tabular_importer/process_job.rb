module TabularImporter
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(import)
      import.transition_to!(:processing, started_at: Time.current) unless import.status == "processing"
      rows = MappedRows.new(import)
      progress = ProgressReporter.new(import, total: rows.count)

      operation = lambda do |_transaction = nil|
        import.definition.processor.call(import:, rows:, progress:).to_h
      end
      summary = if import.definition.transactional?
        ActiveRecord::Base.transaction(requires_new: true, &operation)
      else
        operation.call
      end

      progress.finish("Import complete")
      import.transition_to!(:completed, result_summary: summary, completed_at: Time.current,
        failure_stage: nil, error_class: nil, error_message: nil)
      run_completion_callback(import)
    rescue StandardError => error
      handle_failure(import, error, "processing")
      raise
    end

    private

    def run_completion_callback(import)
      TabularImporter.configuration.after_complete.call(import)
    rescue StandardError => error
      Rails.logger.error("TabularImporter completion callback failed: #{error.message}")
    end

    def handle_failure(import, error, stage)
      import.fail!(error, stage:) unless import.destroyed?
      TabularImporter.configuration.after_failure.call(import, error)
    rescue StandardError => callback_error
      Rails.logger.error("TabularImporter failure callback failed: #{callback_error.message}")
    end
  end
end
