TabularImporter.configure do |config|
  config.authenticate = ->(controller) { controller.send(:authenticate_user!) }
  config.current_actor = ->(controller) { controller.send(:current_user) }
  config.authorize = ->(actor, import, _action) { actor.present? && import.requester == actor }
  config.scope = ->(relation, actor) { relation.where(requester: actor) }

  # config.register :example,
  #   title: "Example import",
  #   columns: [
  #     { key: :external_id, required: true, aliases: ["ID", "Reference"] },
  #     { key: :name, required: true }
  #   ],
  #   analyzer: Imports::ExampleAnalyzer,
  #   processor: Imports::ExampleProcessor
end
