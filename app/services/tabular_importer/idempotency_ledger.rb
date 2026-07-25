module TabularImporter
  class IdempotencyLedger
    def self.call(import:, key:)
      key = key.to_s
      raise ArgumentError, "An idempotency key is required" if key.blank?
      raise ArgumentError, "Idempotency keys cannot exceed 500 characters" if key.bytesize > 500

      executed = false
      IdempotencyRecord.transaction(requires_new: true) do
        IdempotencyRecord.create!(import:, key:)
        yield
        executed = true
      end
      executed
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      duplicate = IdempotencyRecord.exists?(import:, key:)
      raise error unless duplicate
      false
    end
  end
end
