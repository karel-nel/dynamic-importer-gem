require "test_helper"
require "axlsx"

class FileReaderTest < ActiveSupport::TestCase
  test "reads headers, previews, counts, and enumerates CSV rows" do
    import = build_import
    reader = TabularImporter::FileReader.new(import.source_file)

    assert_equal ["CSA ID", "First Name", "Last Name", "Race Time"], reader.headers
    assert_equal 2, reader.preview(limit: 5).size
    assert_equal 2, reader.row_count
    assert_equal 2, reader.to_a.size
    assert_equal [2, 4], reader.each_with_source_row.map { |_row, source_row| source_row }
  end

  test "stops inspection after the configured number of non-empty preview rows" do
    import = build_import
    reader = TabularImporter::FileReader.new(import.source_file)
    TabularImporter.configuration.preview_rows = 2

    reader.define_singleton_method(:each_physical_row) do |&block|
      block.call(["ID", "Name"], 1)
      block.call([nil, ""], 2)
      block.call(["1", "Ada"], 3)
      block.call(["2", "Grace"], 4)
      raise "inspection read beyond the preview rows"
    end

    inspection = reader.inspect_file

    assert_equal ["ID", "Name"], inspection.headers
    assert_equal [["1", "Ada"], ["2", "Grace"]], inspection.preview_rows
  end

  test "reads XLSX files" do
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Results") do |sheet|
      sheet.add_row ["ID", "Name"]
      sheet.add_row ["2001", "Katherine"]
      sheet.add_row ["2002", "Dorothy"]
    end

    file = Tempfile.new(["results", ".xlsx"])
    package.serialize(file.path)
    import = TabularImporter::Import.new(import_type: "people")
    import.source_file.attach(
      io: File.open(file.path),
      filename: "results.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    import.save!

    reader = TabularImporter::FileReader.new(import.source_file)
    assert_equal ["ID", "Name"], reader.headers
    assert_equal [[2001, "Katherine"], [2002, "Dorothy"]], reader.to_a
  ensure
    file&.close!
  end
end
