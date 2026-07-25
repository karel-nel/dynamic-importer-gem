module TabularImporter
  class PreparePreview
    def self.call(import)
      import.reload
      UploadValidator.call(import.source_file)
      reader = FileReader.new(import.source_file)
      inspection = reader.inspect_file
      headers = inspection.headers

      mapping = HeaderMatcher.call(headers:, definition: import.definition)
      import.transition_to!(
        :mapping_required,
        source_headers: headers,
        preview_rows: inspection.preview_rows,
        column_mapping: mapping,
        error_class: nil,
        error_message: nil,
        failure_stage: nil
      )
      import
    end
  end
end
