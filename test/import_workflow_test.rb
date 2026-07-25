require "test_helper"

class ImportWorkflowTest < ActiveSupport::TestCase
  test "previews, automatically maps, analyses, and processes a CSV" do
    import = build_import

    TabularImporter::PreparePreview.call(import)
    assert_equal "mapping_required", import.reload.status
    assert_equal ["CSA ID", "First Name", "Last Name", "Race Time"], import.source_headers
    assert_equal "external_id", import.column_mapping["0"]
    assert_equal "name", import.column_mapping["1"]
    assert_equal 2, import.preview_rows.size

    import.transition_to!(:analyzing)
    TabularImporter::AnalyzeJob.perform_now(import)
    assert_equal "ready", import.reload.status
    assert_equal 2, import.analysis["valid_rows"]

    import.transition_to!(:processing)
    TabularImporter::ProcessJob.perform_now(import)
    assert_equal "completed", import.reload.status
    assert_equal({ "created" => 2 }, import.result_summary)
    assert_equal %w[1001 1002], ProcessedRow.order(:id).pluck(:external_id)
  end

  test "records processor failures and rolls back writes" do
    failing_processor = Class.new do
      def self.call(import:, rows:, progress:)
        ProcessedRow.create!(external_id: "partial", name: "Partial")
        raise "processor exploded"
      end
    end
    TabularImporter.register :failing,
      columns: [{ key: :external_id, required: true, aliases: ["CSA ID"] }],
      processor: failing_processor,
      transactional: true

    import = TabularImporter::Import.new(import_type: "failing")
    path = File.join(__dir__, "fixtures", "files", "results.csv")
    import.source_file.attach(io: File.open(path), filename: "results.csv", content_type: "text/csv")
    import.save!
    TabularImporter::PreparePreview.call(import)
    import.transition_to!(:processing)

    assert_raises(RuntimeError) { TabularImporter::ProcessJob.perform_now(import) }
    assert_equal "failed", import.reload.status
    assert_equal "processing", import.failure_stage
    assert_equal 0, ProcessedRow.count
  end
end
