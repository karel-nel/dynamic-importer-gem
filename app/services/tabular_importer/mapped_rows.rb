module TabularImporter
  class MappedRows
    include Enumerable

    attr_reader :import, :reader, :mapping, :definition

    def initialize(import)
      @import = import
      @reader = FileReader.new(import.source_file)
      @mapping = import.column_mapping.to_h
      @definition = import.definition
    end

    def each
      return enum_for(:each) unless block_given?

      reader.each.with_index(2) do |raw_row, source_row_number|
        mapped = mapping.each_with_object({}) do |(source_index, destination_key), row|
          column = definition.column(destination_key)
          row[destination_key.to_sym] = column.normalize(raw_row[source_index.to_i])
        end
        yield mapped, source_row_number
      end
    end

    def count
      reader.row_count
    end
  end
end
