module TabularImporter
  class RowValidator
    def self.call(definition:, row:)
      definition.columns.each_with_object([]) do |column, errors|
        value = row[column.key.to_sym]
        errors << "#{column.label} is required" if column.required? && value.blank?
        next if value.blank? || column.valid?(value, row:)
        errors << "#{column.label} is invalid"
      rescue StandardError => error
        errors << "#{column.label} is invalid (#{error.message})"
      end
    end
  end
end
