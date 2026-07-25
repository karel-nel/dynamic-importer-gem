module TabularImporter
  class DefaultAnalyzer
    MAX_REPORTED_ERRORS = 100

    def self.call(import:, rows:, progress:)
      valid_rows = 0
      invalid_rows = 0
      invalid_source_rows = []
      errors = []
      total = rows.count

      rows.each.with_index(1) do |(row, source_row_number), current|
        row_errors = RowValidator.call(definition: import.definition, row:)
        if row_errors.empty?
          valid_rows += 1
        else
          invalid_rows += 1
          invalid_source_rows << source_row_number
          errors << { row: source_row_number, errors: row_errors } if errors.size < MAX_REPORTED_ERRORS
        end
        progress.call(current:, total:, message: "Analysing row #{current} of #{total}")
      end

      {
        total_rows: valid_rows + invalid_rows,
        valid_rows:,
        invalid_rows:,
        invalid_source_rows:,
        errors:
      }
    end
  end
end
