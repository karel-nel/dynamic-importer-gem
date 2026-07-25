module TabularImporter
  class Configuration
    attr_accessor :authenticate, :current_actor, :authorize, :scope,
      :after_complete, :after_failure, :max_file_size, :preview_rows,
      :max_rows, :max_columns, :max_cell_bytes, :max_csv_line_bytes, :max_xlsx_entries,
      :max_xlsx_uncompressed_size, :max_xlsx_compression_ratio,
      :processing_lease_timeout, :allowed_content_types
    attr_reader :definitions

    def initialize
      @definitions = {}
      @authenticate = ->(_controller) {}
      @current_actor = lambda do |controller|
        controller.send(:current_user) if controller.respond_to?(:current_user, true)
      end
      @authorize = lambda do |actor, import, _action|
        actor.present? && import.requester == actor
      end
      @scope = lambda do |relation, actor|
        actor&.respond_to?(:to_global_id) ? relation.where(requester: actor) : relation.none
      end
      @after_complete = ->(_import) {}
      @after_failure = ->(_import, _error) {}
      @max_file_size = 25.megabytes
      @preview_rows = 5
      @max_rows = 100_000
      @max_columns = 250
      @max_cell_bytes = 64.kilobytes
      @max_csv_line_bytes = 1.megabyte
      @max_xlsx_entries = 10_000
      @max_xlsx_uncompressed_size = 250.megabytes
      @max_xlsx_compression_ratio = 100
      @processing_lease_timeout = 15.minutes
      @allowed_content_types = {
        "csv" => %w[text/csv text/plain application/csv application/vnd.ms-excel application/octet-stream],
        "xlsx" => %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/zip application/octet-stream]
      }
    end

    def register(key, **options)
      definition = Definition.new(key: key, **options)
      definitions[definition.key] = definition
      definition
    end

    def fetch(key)
      definitions.fetch(key.to_s) do
        raise UnknownImportType, "Unknown import type: #{key.inspect}"
      end
    end
  end
end
