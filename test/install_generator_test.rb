require "test_helper"
require "generators/tabular_importer/install/install_generator"

class InstallGeneratorTest < ActiveSupport::TestCase
  test "copies an initializer and Rails 8 migration" do
    destination = Dir.mktmpdir("tabular-importer-generator")
    generator = TabularImporter::Generators::InstallGenerator.new([], {}, destination_root: destination)
    generator.invoke_all

    initializer = File.join(destination, "config", "initializers", "tabular_importer.rb")
    migration = Dir[File.join(destination, "db", "migrate", "*_create_tabular_importer_imports.rb")].first
    assert File.exist?(initializer)
    assert migration
    assert_includes File.read(migration), "ActiveRecord::Migration[8.0]"
    assert_includes File.read(migration), "t.string :requester_id"
  ensure
    FileUtils.remove_entry(destination) if destination && File.exist?(destination)
  end
end
