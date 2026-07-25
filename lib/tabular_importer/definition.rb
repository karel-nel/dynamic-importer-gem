module TabularImporter
  class Definition
    attr_reader :key, :title, :description, :columns, :analyzer, :processor,
      :transactional, :metadata_validator, :mapping_validator, :presenter,
      :allow_partial_imports, :back_url

    def initialize(key:, columns:, processor:, analyzer: nil, title: nil, description: nil,
                   transactional: false, metadata_validator: nil, mapping_validator: nil,
                   presenter: nil, allow_partial_imports: false, back_url: nil)
      @key = key.to_s
      @title = title.presence || key.to_s.humanize
      @description = description
      @columns = Array(columns).map { |column| column.is_a?(Column) ? column : Column.new(**column) }
      @analyzer = analyzer
      @processor = processor
      @transactional = transactional
      @metadata_validator = metadata_validator
      @mapping_validator = mapping_validator
      @presenter = presenter
      @allow_partial_imports = allow_partial_imports
      @back_url = back_url

      validate!
    end

    def column(key)
      columns.find { |column| column.key == key.to_s }
    end

    def required_columns
      columns.select(&:required?)
    end

    def transactional?
      !!transactional
    end

    def allow_partial_imports?
      !!allow_partial_imports
    end

    def back_url_for(controller)
      back_url.respond_to?(:call) ? back_url.call(controller) : back_url
    end

    def analyze_with
      analyzer || TabularImporter::DefaultAnalyzer
    end

    private

    def validate!
      raise ArgumentError, "an import type needs at least one column" if columns.empty?
      raise ArgumentError, "column keys must be unique" unless columns.map(&:key).uniq.size == columns.size
      raise ArgumentError, "processor must respond to .call" unless processor.respond_to?(:call)
      raise ArgumentError, "analyzer must respond to .call" if analyzer && !analyzer.respond_to?(:call)
      raise ArgumentError, "mapping_validator must respond to .call" if mapping_validator && !mapping_validator.respond_to?(:call)
      raise ArgumentError, "presenter must respond to .call" if presenter && !presenter.respond_to?(:call)
      unless back_url.nil? || back_url.is_a?(String) || back_url.respond_to?(:call)
        raise ArgumentError, "back_url must be a String or respond to .call"
      end
    end
  end
end
