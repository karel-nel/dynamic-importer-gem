module TabularImporter
  class DefaultAnalyzer
    MAX_REPORTED_ERRORS = 100

    def self.call(import:, rows:, progress:)
      valid_rows = 0
      invalid_rows = 0
      errors = []
      total = rows.count

      rows.each.with_index(1) do |(row, source_row_number), current|
        row_errors = validate_row(import.definition, row)
        if row_errors.empty?
          valid_rows += 1
        else
          invalid_rows += 1
          errors << { row: source_row_number, errors: row_errors } if errors.size < MAX_REPORTED_ERRORS
        end
        progress.call(current:, total:, message: "Analysing row #{current} of #{total}")
      end

      {
        total_rows: valid_rows + invalid_rows,
        valid_rows:,
        invalid_rows:,
        errors:
      }
    end

    def self.validate_row(definition, row)
      definition.columns.each_with_object([]) do |column, errors|
        value = row[column.key.to_sym]
        errors << "#{column.label} is required" if column.required? && value.blank?
        next if value.blank? || column.valid?(value, row:)
        errors << "#{column.label} is invalid"
      rescue StandardError => error
        errors << "#{column.label} is invalid (#{error.message})"
      end
    end
    private_class_method :validate_row
  end
end
