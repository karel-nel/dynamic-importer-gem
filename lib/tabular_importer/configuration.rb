module TabularImporter
  class Configuration
    attr_accessor :authenticate, :current_actor, :authorize, :scope,
      :after_complete, :after_failure, :max_file_size, :preview_rows
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
