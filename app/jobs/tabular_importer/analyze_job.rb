module TabularImporter
  class AnalyzeJob < ApplicationJob
    queue_as :default

    def perform(import)
      import.transition_to!(:analyzing, started_at: Time.current) unless import.status == "analyzing"
      rows = MappedRows.new(import)
      progress = ProgressReporter.new(import, total: rows.count)
      analysis = import.definition.analyze_with.call(import:, rows:, progress:)
      progress.finish("Analysis complete")
      import.transition_to!(:ready, analysis: analysis.to_h, failure_stage: nil, error_class: nil, error_message: nil)
    rescue StandardError => error
      handle_failure(import, error, "analysis")
      raise
    end

    private

    def handle_failure(import, error, stage)
      import.fail!(error, stage:) unless import.destroyed?
      TabularImporter.configuration.after_failure.call(import, error)
    rescue StandardError => callback_error
      Rails.logger.error("TabularImporter failure callback failed: #{callback_error.message}")
    end
  end
end
