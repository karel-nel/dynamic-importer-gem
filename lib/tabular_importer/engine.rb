module TabularImporter
  class Engine < ::Rails::Engine
    isolate_namespace TabularImporter

    initializer "tabular_importer.assets" do |app|
      next unless app.config.respond_to?(:assets)
      app.config.assets.precompile += %w[tabular_importer/application.css tabular_importer/application.js]
    end
  end
end
