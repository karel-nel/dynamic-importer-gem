module TabularImporter
  class FileReader
    include Enumerable

    Inspection = Struct.new(:headers, :preview_rows, keyword_init: true)

    attr_reader :attachment

    def initialize(attachment)
      @attachment = attachment
      raise UnsupportedFile, "No source file is attached" unless attachment.attached?
    end

    def inspect_file
      @inspection ||= begin
        headers = nil
        preview_rows = []
        preview_limit = [configuration.preview_rows.to_i, 0].max

        each_physical_row do |row, source_row_number|
          validate_row_limits!(row, source_row_number)
          if headers.nil?
            headers = row
            break if preview_limit.zero?
            next
          end
          next if row.all?(&:blank?)

          preview_rows << row
          enforce_maximum!(:max_rows, preview_rows.size, "data rows")
          break if preview_rows.size >= preview_limit
        end

        if headers.nil? || headers.all?(&:blank?)
          raise UnsupportedFile, "The uploaded file has no header row"
        end

        Inspection.new(headers:, preview_rows:)
      end
    end

    def headers
      inspect_file.headers
    end

    def preview(limit: configuration.preview_rows)
      inspect_file.preview_rows.first(limit.to_i)
    end

    def each
      return enum_for(:each) unless block_given?
      each_with_source_row { |row, _source_row_number| yield row }
    end

    def each_with_source_row
      return enum_for(:each_with_source_row) unless block_given?

      header_seen = false
      data_rows = 0
      each_physical_row do |row, source_row_number|
        validate_row_limits!(row, source_row_number)
        unless header_seen
          header_seen = true
          next
        end
        next if row.all?(&:blank?)

        data_rows += 1
        enforce_maximum!(:max_rows, data_rows, "data rows")
        yield row, source_row_number
      end
    end

    def row_count
      return @row_count if defined?(@row_count)

      @row_count = 0
      each_with_source_row { @row_count += 1 }
      @row_count
    end

    private

    def each_physical_row
      attachment.open do |file|
        case extension
        when "csv"
          verify_csv_signature!(file.path)
          each_csv_row(file.path) { |row, number| yield row, number }
        when "xlsx"
          verify_xlsx_archive!(file.path)
          each_xlsx_row(file.path) { |row, number| yield row, number }
        else
          raise UnsupportedFile, "Only CSV and XLSX files are supported"
        end
      end
    rescue UnsupportedFile
      raise
    rescue Zip::Error, CSV::MalformedCSVError, EncodingError, ArgumentError, TypeError => error
      raise UnsupportedFile, "The uploaded file could not be read: #{error.message}"
    end

    def each_csv_row(path)
      CSV.open(path, "r:bom|utf-8") do |csv|
        next_physical_line = 1
        loop do
          row = csv.shift
          break unless row
          source_row_number = next_physical_line
          consumed_lines = csv.line.to_s.each_line.count
          next_physical_line += [consumed_lines, 1].max
          yield normalize_row(row), source_row_number
        end
      end
    end

    def each_xlsx_row(path)
      spreadsheet = Roo::Excelx.new(path)
      sheet = spreadsheet.sheet(0)
      enforce_maximum!(:max_rows, [sheet.last_row.to_i - 1, 0].max, "physical worksheet rows")
      enforce_maximum!(:max_columns, sheet.last_column.to_i, "worksheet columns")

      (1..sheet.last_row.to_i).each do |number|
        yield normalize_row(sheet.row(number)), number
      end
    ensure
      spreadsheet&.close if spreadsheet.respond_to?(:close)
    end

    def verify_csv_signature!(path)
      sample = File.binread(path, [File.size(path), 8.kilobytes].min)
      raise UnsupportedFile, "CSV files cannot contain NUL bytes" if sample.include?("\0")
    end

    def verify_xlsx_archive!(path)
      signature = File.binread(path, 4)
      raise UnsupportedFile, "The XLSX file does not have a valid ZIP signature" unless signature.start_with?("PK")

      Zip::File.open(path) do |archive|
        entries = archive.entries
        enforce_maximum!(:max_xlsx_entries, entries.size, "XLSX archive entries")

        uncompressed_size = entries.sum(&:size)
        enforce_maximum!(:max_xlsx_uncompressed_size, uncompressed_size, "uncompressed XLSX bytes")

        entries.each do |entry|
          if entry.respond_to?(:encrypted?) && entry.encrypted?
            raise UnsupportedFile, "Encrypted XLSX files are not supported"
          end
          next if entry.size.zero?

          compressed_size = entry.compressed_size.to_i
          ratio = compressed_size.zero? ? Float::INFINITY : entry.size.to_f / compressed_size
          if ratio > configuration.max_xlsx_compression_ratio
            raise UnsupportedFile, "The XLSX compression ratio exceeds the configured safety limit"
          end
        end
      end
    end

    def validate_row_limits!(row, source_row_number)
      enforce_maximum!(:max_columns, row.length, "columns on source row #{source_row_number}")
      row.each do |value|
        next if value.nil?
        enforce_maximum!(:max_cell_bytes, value.to_s.bytesize, "bytes in a cell on source row #{source_row_number}")
      end
    end

    def enforce_maximum!(setting, actual, label)
      maximum = configuration.public_send(setting).to_i
      return if maximum <= 0 || actual <= maximum
      message = if setting == :max_rows
        "Source row limit exceeded (configured limit of #{maximum})"
      else
        "#{label.to_s.humanize} exceed the configured limit of #{maximum}"
      end
      raise ResourceLimitExceeded, message
    end

    def normalize_row(row)
      Array(row).map { |value| value.is_a?(String) ? value.strip : value }
    end

    def extension
      attachment.filename.extension.to_s.downcase
    end

    def configuration
      TabularImporter.configuration
    end
  end
end
