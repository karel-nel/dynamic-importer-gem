require "test_helper"

class UploadValidationTest < ActiveSupport::TestCase
  test "rejects content types that do not match the extension" do
    import = TabularImporter::Import.new(import_type: "people")
    path = File.join(__dir__, "fixtures", "files", "results.csv")
    import.source_file.attach(io: File.open(path), filename: "results.csv", content_type: "image/png")

    refute import.valid?
    assert import.errors[:source_file].any? { |message| message.include?("content type") }
  end

  test "rejects files whose bytes do not match XLSX" do
    import = TabularImporter::Import.new(import_type: "people")
    path = File.join(__dir__, "fixtures", "files", "results.csv")
    import.source_file.attach(
      io: File.open(path),
      filename: "results.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    import.save!

    assert_raises(TabularImporter::UnsupportedFile) { TabularImporter::PreparePreview.call(import) }
  end

  test "enforces configured row limits before preview" do
    TabularImporter.configuration.max_rows = 1
    import = build_import

    error = assert_raises(TabularImporter::ResourceLimitExceeded) do
      TabularImporter::PreparePreview.call(import)
    end
    assert_includes error.message, "row limit"
  end

  test "enforces configured cell limits" do
    TabularImporter.configuration.max_cell_bytes = 3
    import = build_import

    error = assert_raises(TabularImporter::UnsupportedFile) do
      TabularImporter::PreparePreview.call(import)
    end
    assert_includes error.message, "cell"
  end

  test "enforces configured CSV line limits" do
    TabularImporter.configuration.max_csv_line_bytes = 10
    import = build_import

    error = assert_raises(TabularImporter::ResourceLimitExceeded) do
      TabularImporter::PreparePreview.call(import)
    end
    assert_includes error.message, "CSV line"
  end
end
