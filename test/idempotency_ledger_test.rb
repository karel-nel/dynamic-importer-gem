require "test_helper"

class IdempotencyLedgerTest < ActiveSupport::TestCase
  test "executes a database effect once for a durable import-scoped key" do
    import = build_import

    first = import.idempotently("result:source-row:2") do
      ProcessedRow.create!(external_id: "1001", name: "Ada")
    end
    second = import.idempotently("result:source-row:2") do
      ProcessedRow.create!(external_id: "duplicate", name: "Duplicate")
    end

    assert first
    refute second
    assert_equal 1, ProcessedRow.count
    assert_equal 1, import.idempotency_records.count
  end

  test "rolls back the key and database effect when the block fails" do
    import = build_import

    assert_raises(RuntimeError) do
      import.idempotently("result:source-row:2") do
        ProcessedRow.create!(external_id: "partial", name: "Partial")
        raise "failed"
      end
    end

    assert_equal 0, ProcessedRow.count
    assert_equal 0, import.idempotency_records.count
    assert import.idempotently("result:source-row:2") { ProcessedRow.create!(external_id: "retry", name: "Retry") }
  end

  test "provides stable keys for external idempotency APIs" do
    import = build_import
    assert_equal "#{import.idempotency_key}:source-row:2", import.idempotency_key_for("source-row:2")
  end
end
