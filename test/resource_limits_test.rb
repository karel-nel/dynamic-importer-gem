require "test_helper"

class ResourceLimitsTest < ActiveSupport::TestCase
  test "enforces the maximum data row count" do
    TabularImporter.configuration.max_rows = 1
    import = build_import

    error = assert_raises(TabularImporter::UnsupportedFile) do
      TabularImporter::PreparePreview.call(import)
    end
    assert_includes error.message, "limit of 1"
  end

  test "enforces column and cell size limits" do
    TabularImporter.configuration.max_columns = 3
    import = build_import
    assert_raises(TabularImporter::UnsupportedFile) { TabularImporter::PreparePreview.call(import) }

    TabularImporter.configuration.max_columns = 250
    TabularImporter.configuration.max_cell_bytes = 3
    error = assert_raises(TabularImporter::UnsupportedFile) do
      TabularImporter::PreparePreview.call(import)
    end
    assert_includes error.message, "cell"
  end

  test "rejects a mismatched declared content type" do
    import = TabularImporter::Import.new(import_type: "people")
    path = File.join(__dir__, "fixtures", "files", "results.csv")
    import.source_file.attach(io: File.open(path), filename: "results.csv", content_type: "image/png")

    refute import.valid?
    assert import.errors[:source_file].any? { |message| message.include?("content type") }
  end

  test "rejects an invalid XLSX signature before parsing" do
    import = TabularImporter::Import.new(import_type: "people")
    path = File.join(__dir__, "fixtures", "files", "results.csv")
    import.source_file.attach(
      io: File.open(path),
      filename: "fake.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    import.save!

    error = assert_raises(TabularImporter::UnsupportedFile) do
      TabularImporter::PreparePreview.call(import)
    end
    assert_includes error.message, "ZIP signature"
  end

  test "allows individual numeric resource guards to be disabled with zero" do
    config = TabularImporter.configuration
    config.max_file_size = 0
    config.max_rows = 0
    config.max_columns = 0
    config.max_cell_bytes = 0
    config.max_csv_line_bytes = 0

    import = build_import
    assert TabularImporter::PreparePreview.call(import)
    assert_equal 2, import.reload.preview_rows.size
  end
end
