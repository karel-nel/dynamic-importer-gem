module TabularImporter
  class FileReader
    include Enumerable

    attr_reader :attachment

    def initialize(attachment)
      @attachment = attachment
      raise UnsupportedFile, "No source file is attached" unless attachment.attached?
    end

    def headers
      with_sheet { |sheet| normalize_row(sheet.row(1)) }
    end

    def preview(limit: TabularImporter.configuration.preview_rows)
      with_sheet do |sheet|
        last_row = [sheet.last_row.to_i, limit.to_i + 1].min
        next [] if last_row < 2
        (2..last_row).map { |number| normalize_row(sheet.row(number)) }
      end
    end

    def each
      return enum_for(:each) unless block_given?

      with_sheet do |sheet|
        next if sheet.last_row.to_i < 2
        (2..sheet.last_row).each do |number|
          row = normalize_row(sheet.row(number))
          yield row unless row.all?(&:blank?)
        end
      end
    end

    def row_count
      with_sheet do |sheet|
        next 0 if sheet.last_row.to_i < 2
        (2..sheet.last_row).count { |number| normalize_row(sheet.row(number)).any?(&:present?) }
      end
    end

    private

    def with_sheet
      attachment.open do |file|
        spreadsheet = open_spreadsheet(file.path)
        yield spreadsheet.sheet(0)
      ensure
        spreadsheet&.close if spreadsheet.respond_to?(:close)
      end
    rescue Zip::Error, CSV::MalformedCSVError, ArgumentError => error
      raise UnsupportedFile, "The uploaded file could not be read: #{error.message}"
    end

    def open_spreadsheet(path)
      case attachment.filename.extension.to_s.downcase
      when "csv"
        Roo::CSV.new(path, csv_options: { encoding: "bom|utf-8" })
      when "xlsx"
        Roo::Excelx.new(path)
      else
        raise UnsupportedFile, "Only CSV and XLSX files are supported"
      end
    end

    def normalize_row(row)
      Array(row).map { |value| value.is_a?(String) ? value.strip : value }
    end
  end
end
