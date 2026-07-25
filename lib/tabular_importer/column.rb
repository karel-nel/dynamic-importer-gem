module TabularImporter
  class Column
    attr_reader :key, :label, :aliases, :required, :normalizer, :validator

    def initialize(key:, label: nil, aliases: [], required: false, normalizer: nil, validator: nil)
      @key = key.to_s
      @label = label.presence || key.to_s.humanize
      @aliases = Array(aliases).map { |value| normalize_header(value) }.uniq
      @required = required
      @normalizer = normalizer
      @validator = validator
    end

    def required?
      !!required
    end

    def matches_header?(header)
      candidates.include?(normalize_header(header))
    end

    def normalize(value)
      return value unless normalizer
      normalizer.respond_to?(:call) ? normalizer.call(value) : value.public_send(normalizer)
    end

    def valid?(value, row: nil)
      return true unless validator
      validator.arity == 1 ? validator.call(value) : validator.call(value, row)
    end

    private

    def candidates
      @candidates ||= ([key, label] + aliases).map { |value| normalize_header(value) }.uniq
    end

    def normalize_header(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end
