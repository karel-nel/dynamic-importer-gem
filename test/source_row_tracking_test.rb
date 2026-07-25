require "test_helper"

class SourceRowTrackingTest < ActiveSupport::TestCase
  test "preserves physical CSV lines when blank rows are skipped" do
    import = build_import(filename: "results_with_blanks.csv")
    reader = TabularImporter::FileReader.new(import.source_file)

    rows = reader.each_with_source_row.to_a
    assert_equal [2, 4], rows.map(&:last)
    assert_equal %w[3001 3002], rows.map { |row, _number| row.first }
  end

  test "analysis errors identify the physical source row" do
    import = build_import(filename: "results_with_blanks.csv")
    TabularImporter::PreparePreview.call(import)
    import.transition_to!(:analyzing)
    TabularImporter::AnalyzeJob.perform_now(import)

    assert_equal 1, import.reload.analysis["invalid_rows"]
    assert_equal 4, import.analysis["errors"].first["row"]
  end

  test "reports the starting physical line for multiline CSV records" do
    import = build_import(filename: "results_multiline.csv")
    rows = TabularImporter::FileReader.new(import.source_file).each_with_source_row.to_a

    assert_equal [2, 5], rows.map(&:last)
    assert_equal "Ada\nLovelace", rows.first.first[1]
  end
end
