module TabularImporter
  class MappingValidator
    def self.call(definition:, headers:, mapping:)
      new(definition:, headers:, mapping:).call
    end

    def initialize(definition:, headers:, mapping:)
      @definition = definition
      @headers = Array(headers)
      @mapping = mapping.to_h.transform_keys(&:to_s).transform_values(&:to_s).reject { |_key, value| value.blank? }
    end

    def call
      errors = []
      invalid_indexes = @mapping.keys.reject { |index| integer_string?(index) && index.to_i < @headers.length }
      errors << "The mapping contains unknown source columns" if invalid_indexes.any?

      unknown_columns = @mapping.values - @definition.columns.map(&:key)
      errors << "Unknown destination columns: #{unknown_columns.join(', ')}" if unknown_columns.any?

      duplicates = @mapping.values.tally.select { |_key, count| count > 1 }.keys
      errors << "Each destination column can only be selected once: #{duplicates.join(', ')}" if duplicates.any?

      missing = @definition.required_columns.map(&:key) - @mapping.values
      errors << "Required columns are missing: #{missing.join(', ')}" if missing.any?

      if errors.empty? && @definition.mapping_validator
        result = @definition.mapping_validator.call(@mapping)
        unless result == true
          custom_errors = Array(result).compact
          errors.concat(custom_errors.presence || ["The selected column mapping is invalid"])
        end
      end

      raise InvalidMapping, errors if errors.any?
      @mapping
    end

    private

    def integer_string?(value)
      value.match?(/\A\d+\z/)
    end
  end
end
