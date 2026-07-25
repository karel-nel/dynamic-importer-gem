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

  test "supports fixed and callable back URLs" do
    fixed = TabularImporter.register :fixed_back,
      columns: [{ key: :id }],
      processor: TestProcessor,
      back_url: "/members"
    callable = TabularImporter.register :callable_back,
      columns: [{ key: :id }],
      processor: TestProcessor,
      back_url: ->(controller) { "/members/#{controller}" }

    assert_equal "/members", fixed.back_url_for(Object.new)
    assert_equal "/members/dashboard", callable.back_url_for("dashboard")
  end

  test "rejects an invalid back URL" do
    assert_raises(ArgumentError) do
      TabularImporter.register :invalid_back,
        columns: [{ key: :id }],
        processor: TestProcessor,
        back_url: 123
    end
  end
end
