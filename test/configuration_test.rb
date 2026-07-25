require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  test "registers and resolves a definition" do
    definition = TabularImporter.definition(:people)
    assert_equal "People", definition.title
    assert_equal %w[external_id name last_name race_time], definition.columns.map(&:key)
  end

  test "rejects duplicate column keys" do
    assert_raises(ArgumentError) do
      TabularImporter.register :invalid,
        columns: [{ key: :id }, { key: :id }],
        processor: TestProcessor
    end
  end

  test "raises for unknown import types" do
    assert_raises(TabularImporter::UnknownImportType) { TabularImporter.definition(:missing) }
  end
end
