require "test_helper"

class MappingValidatorTest < ActiveSupport::TestCase
  test "accepts a complete unique mapping" do
    mapping = TabularImporter::MappingValidator.call(
      definition: TabularImporter.definition(:people),
      headers: ["ID", "Name"],
      mapping: { "0" => "external_id", "1" => "name" }
    )
    assert_equal({ "0" => "external_id", "1" => "name" }, mapping)
  end

  test "rejects missing required and duplicate destination columns" do
    error = assert_raises(TabularImporter::InvalidMapping) do
      TabularImporter::MappingValidator.call(
        definition: TabularImporter.definition(:people),
        headers: ["ID", "Name"],
        mapping: { "0" => "external_id", "1" => "external_id" }
      )
    end
    assert error.errors.any? { |message| message.include?("only be selected once") }
    assert error.errors.any? { |message| message.include?("name") }
  end
end
