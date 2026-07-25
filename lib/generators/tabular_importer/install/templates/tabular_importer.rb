TabularImporter.configure do |config|
  config.authenticate = ->(controller) { controller.send(:authenticate_user!) }
  config.current_actor = ->(controller) { controller.send(:current_user) }
  config.authorize = ->(actor, import, _action) { actor.present? && import.requester == actor }
  config.scope = ->(relation, actor) { relation.where(requester: actor) }

  # Practical upload and decompression limits. Set a numeric limit to 0 to
  # disable that individual guard only after assessing the resource risk.
  config.max_file_size = 25.megabytes
  config.max_rows = 100_000
  config.max_columns = 250
  config.max_cell_bytes = 64.kilobytes
  config.max_csv_line_bytes = 1.megabyte
  config.max_xlsx_entries = 10_000
  config.max_xlsx_uncompressed_size = 250.megabytes
  config.max_xlsx_compression_ratio = 100
  config.processing_lease_timeout = 15.minutes

  # config.register :example,
  #   title: "Example import",
  #   columns: [
  #     { key: :external_id, required: true, aliases: ["ID", "Reference"] },
  #     { key: :name, required: true }
  #   ],
  #   analyzer: Imports::ExampleAnalyzer,
  #   processor: Imports::ExampleProcessor,
  #   allow_partial_imports: false,
  #   back_url: ->(controller) { controller.main_app.root_path }
end
