module TabularImporter
  class PreparePreview
    def self.call(import)
      import.reload
      reader = FileReader.new(import.source_file)
      headers = reader.headers
      raise UnsupportedFile, "The uploaded file has no header row" if headers.empty? || headers.all?(&:blank?)

      mapping = HeaderMatcher.call(headers:, definition: import.definition)
      import.transition_to!(
        :mapping_required,
        source_headers: headers,
        preview_rows: reader.preview,
        column_mapping: mapping,
        error_class: nil,
        error_message: nil,
        failure_stage: nil
      )
      import
    end
  end
end
