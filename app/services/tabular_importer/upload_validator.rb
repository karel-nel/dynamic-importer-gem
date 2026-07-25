module TabularImporter
  class UploadValidator
    ZIP_MAGIC = "PK".b

    def self.call(attachment)
      new(attachment).call
    end

    def initialize(attachment)
      @attachment = attachment
      @config = TabularImporter.configuration
    end

    def call
      raise UnsupportedFile, "No source file is attached" unless @attachment.attached?
      validate_blob_metadata!

      @attachment.open do |file|
        extension == "xlsx" ? validate_xlsx!(file.path) : validate_csv!(file.path)
      end
      true
    end

    private

    def extension
      @extension ||= @attachment.filename.extension.to_s.downcase
    end

    def validate_blob_metadata!
      raise UnsupportedFile, "Only CSV and XLSX files are supported" unless extension.in?(%w[csv xlsx])
      raise UnsupportedFile, "The uploaded file is empty" if @attachment.blob.byte_size.zero?
      if limit_enabled?(@config.max_file_size) && @attachment.blob.byte_size > @config.max_file_size
        raise ResourceLimitExceeded, "The uploaded file exceeds the #{human_size(@config.max_file_size)} limit"
      end

      content_type = @attachment.blob.content_type.to_s.downcase
      allowed = @config.allowed_content_types.fetch(extension, [])
      unless content_type.in?(allowed)
        raise UnsupportedFile, "The declared content type is not valid for a #{extension.upcase} file"
      end
    end

    def validate_csv!(path)
      File.open(path, "rb") do |file|
        signature = file.read(8.kilobytes).to_s
        raise UnsupportedFile, "CSV files cannot contain null bytes" if signature.include?("\0")
        file.rewind
        file.each_line do |line|
          if limit_enabled?(@config.max_csv_line_bytes) && line.bytesize > @config.max_csv_line_bytes
            raise ResourceLimitExceeded, "A CSV line exceeds the #{human_size(@config.max_csv_line_bytes)} limit"
          end
        end
      end
    end

    def validate_xlsx!(path)
      File.open(path, "rb") do |file|
        raise UnsupportedFile, "The XLSX file does not have a valid ZIP signature" unless file.read(2) == ZIP_MAGIC
      end

      Zip::File.open(path) do |archive|
        if limit_enabled?(@config.max_xlsx_entries) && archive.entries.size > @config.max_xlsx_entries
          raise ResourceLimitExceeded, "The XLSX archive exceeds the #{@config.max_xlsx_entries} entry limit"
        end

        uncompressed = 0
        compressed = 0
        archive.each do |entry|
          if unsafe_entry_name?(entry.name)
            raise UnsupportedFile, "The XLSX archive contains an unsafe entry path"
          end
          uncompressed += entry.size.to_i
          compressed += entry.compressed_size.to_i
        end

        if limit_enabled?(@config.max_xlsx_uncompressed_size) && uncompressed > @config.max_xlsx_uncompressed_size
          raise ResourceLimitExceeded, "The expanded XLSX exceeds the #{human_size(@config.max_xlsx_uncompressed_size)} limit"
        end

        ratio = compressed.positive? ? uncompressed.to_f / compressed : uncompressed.to_f
        if limit_enabled?(@config.max_xlsx_compression_ratio) && ratio > @config.max_xlsx_compression_ratio
          raise ResourceLimitExceeded, "The XLSX compression ratio exceeds the configured safety limit"
        end
      end
    rescue Zip::Error => error
      raise UnsupportedFile, "The XLSX archive is invalid: #{error.message}"
    end

    def unsafe_entry_name?(name)
      name.start_with?("/", "\\") || name.split(/[\\\/]/).include?("..")
    end

    def human_size(bytes)
      ActiveSupport::NumberHelper.number_to_human_size(bytes)
    end

    def limit_enabled?(value)
      value.to_i.positive?
    end
  end
end
