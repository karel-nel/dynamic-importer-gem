require "rails/generators"
require "rails/generators/migration"

module TabularImporter
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        next_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_number)
      end

      def copy_migration
        migration_template "create_tabular_importer_imports.rb", "db/migrate/create_tabular_importer_imports.rb"
      end

      def copy_initializer
        template "tabular_importer.rb", "config/initializers/tabular_importer.rb"
      end

      def show_next_steps
        say "Mount the engine in config/routes.rb:"
        say "  mount TabularImporter::Engine => '/imports', as: :tabular_importer", :green
        say "Run bin/rails active_storage:install if Active Storage is not installed."
        say "Then run bin/rails db:migrate."
      end
    end
  end
end
