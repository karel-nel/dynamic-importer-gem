module TabularImporter
  class ProgressReporter
    attr_reader :import, :total

    def initialize(import, total:)
      @import = import
      @total = total.to_i
      @last_write_at = nil
      @last_current = -1
      call(current: 0, total: @total, message: "Starting")
    end

    def call(current:, total: @total, message: nil, force: false)
      current = current.to_i
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if !force && current != total.to_i && @last_write_at && now - @last_write_at < 0.5

      import.update_progress!(current:, total:, message:)
      @last_write_at = now
      @last_current = current
    end

    def finish(message = "Complete")
      call(current: total, total:, message:, force: true)
    end
  end
end
