require "test_helper"

class PartialImportTest < ActiveSupport::TestCase
  def analyzed_import(import_type:, allow_partial_imports:)
    TabularImporter.register import_type,
      title: "People",
      columns: [
        { key: :external_id, required: true, aliases: ["ID"] },
        { key: :name, required: true, aliases: ["Name"] }
      ],
      processor: TestProcessor,
      allow_partial_imports: allow_partial_imports

    import = build_import(filename: "invalid_results.csv", import_type:)
    TabularImporter::PreparePreview.call(import)
    import.transition_to!(:analyzing)
    TabularImporter::AnalyzeJob.perform_now(import)
    import.reload
  end

  test "blocks invalid analysis unless partial imports are explicitly enabled" do
    import = analyzed_import(import_type: :strict_people, allow_partial_imports: false)
    assert_equal 1, import.invalid_rows_count
    assert_equal [3], import.invalid_source_rows

    error = assert_raises(TabularImporter::InvalidState) do
      import.begin_processing!(partial_import_confirmed: true)
    end
    assert_includes error.message, "blocked"
    assert_equal "ready", import.reload.status
  end

  test "requires confirmation and automatically excludes reported invalid source rows" do
    import = analyzed_import(import_type: :partial_people, allow_partial_imports: true)
    assert_raises(TabularImporter::InvalidState) { import.begin_processing!(partial_import_confirmed: false) }

    import.begin_processing!(partial_import_confirmed: true)
    TabularImporter::ProcessJob.perform_now(import)

    assert import.reload.completed?
    assert import.partial_import_confirmed?
    assert_equal %w[2001 2003], ProcessedRow.order(:id).pluck(:external_id)
    assert_equal 2, import.result_summary["created"]
  end

  test "blocks partial processing when a custom analyser omits physical invalid rows" do
    analyzer = Class.new do
      def self.call(import:, rows:, progress:)
        { total_rows: rows.count, valid_rows: rows.count - 1, invalid_rows: 1 }
      end
    end
    TabularImporter.register :incomplete_partial_people,
      columns: [{ key: :external_id, required: true, aliases: ["ID"] }],
      analyzer:,
      processor: TestProcessor,
      allow_partial_imports: true

    import = build_import(filename: "invalid_results.csv", import_type: :incomplete_partial_people)
    TabularImporter::PreparePreview.call(import)
    import.transition_to!(:analyzing)
    TabularImporter::AnalyzeJob.perform_now(import)

    error = assert_raises(TabularImporter::InvalidState) do
      import.reload.begin_processing!(partial_import_confirmed: true)
    end
    assert_includes error.message, "invalid_source_rows"
  end
end
