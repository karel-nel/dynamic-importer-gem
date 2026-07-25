require "test_helper"

class IdempotencyTest < ActiveSupport::TestCase
  test "assigns a stable unique idempotency key" do
    first = build_import
    second = build_import

    assert_match(/\A[0-9a-f-]{36}\z/, first.idempotency_key)
    refute_equal first.idempotency_key, second.idempotency_key

    original = first.idempotency_key
    first.transition_to!(:failed)
    first.transition_to!(:processing)
    assert_equal original, first.reload.idempotency_key
  end

  test "uses a durable execution lease and reclaims a stale claim" do
    import = build_import
    import.transition_to!(:processing)

    assert import.claim_processing!("execution-one")
    refute import.claim_processing!("execution-two")
    assert_equal 1, import.reload.processor_attempts

    import.update_columns(processor_heartbeat_at: 1.hour.ago)
    assert import.claim_processing!("execution-two")
    assert_equal "execution-two", import.reload.processor_execution_id
    assert_equal 2, import.processor_attempts
  end

  test "a completed duplicate job does not process rows twice" do
    import = build_import
    TabularImporter::PreparePreview.call(import)
    import.transition_to!(:processing)

    TabularImporter::ProcessJob.perform_now(import)
    assert_equal 2, ProcessedRow.count
    TabularImporter::ProcessJob.perform_now(import.reload)
    assert_equal 2, ProcessedRow.count
  end
end
