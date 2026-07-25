module TabularImporter
  class MappedRows
    include Enumerable

    attr_reader :import, :reader, :mapping, :definition

    def initialize(import, excluded_source_rows: [])
      @import = import
      @reader = FileReader.new(import.source_file)
      @mapping = import.column_mapping.to_h
      @definition = import.definition
      @excluded_source_rows = Set.new(Array(excluded_source_rows).map(&:to_i))
    end

    def each
      return enum_for(:each) unless block_given?

      reader.each_with_source_row do |raw_row, source_row_number|
        next if @excluded_source_rows.include?(source_row_number)
        mapped = mapping.each_with_object({}) do |(source_index, destination_key), row|
          column = definition.column(destination_key)
          row[destination_key.to_sym] = column.normalize(raw_row[source_index.to_i])
        end
        yield mapped, source_row_number
      end
    end

    def count
      reader.each_with_source_row.count do |_row, source_row_number|
        !@excluded_source_rows.include?(source_row_number)
      end
    end
  end
end
