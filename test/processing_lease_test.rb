require "test_helper"

class ProcessingLeaseTest < ActiveSupport::TestCase
  test "prevents a second job from claiming an active processing lease" do
    import = build_import
    TabularImporter::PreparePreview.call(import)
    import.update!(status: "ready")
    import.begin_processing!

    assert import.claim_processing!("job-one")
    refute import.claim_processing!("job-two")
    assert_equal "job-one", import.reload.processor_execution_id
  end

  test "allows a new job to recover an expired lease" do
    import = build_import
    TabularImporter::PreparePreview.call(import)
    import.update!(status: "ready")
    import.begin_processing!
    import.claim_processing!("job-one")
    TabularImporter::Import.where(id: import.id).update_all(processor_heartbeat_at: 1.hour.ago)
    import.reload

    assert import.claim_processing!("job-two")
    assert_equal "job-two", import.reload.processor_execution_id
  end

  test "a stale worker cannot heartbeat a reclaimed lease" do
    import = build_import
    TabularImporter::PreparePreview.call(import)
    import.update!(status: "ready")
    import.begin_processing!
    import.claim_processing!("job-one")
    stale_progress = TabularImporter::ProgressReporter.new(import, total: 2, execution_id: "job-one")

    TabularImporter::Import.where(id: import.id).update_all(processor_heartbeat_at: 1.hour.ago)
    import.reload
    assert import.claim_processing!("job-two")

    assert_raises(TabularImporter::ProcessingLeaseUnavailable) do
      stale_progress.call(current: 1, total: 2, message: "Old worker", force: true)
    end
    assert_equal "job-two", import.reload.processor_execution_id
  end
end
