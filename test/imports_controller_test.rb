require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  def setup
    super
    @actor = TestActor.create!(name: "Uploader")
    TabularImporter.configuration.current_actor = ->(_controller) { @actor }
    TabularImporter.configuration.authorize = ->(actor, import, _action) { actor == import.requester }
    TabularImporter.configuration.scope = ->(relation, actor) { relation.where(requester: actor) }
  end

  test "renders the index and new import form" do
    get "/imports"
    assert_response :success
    assert_includes response.body, "Data imports"

    get "/imports/new", params: { import_type: "people" }
    assert_response :success
    assert_includes response.body, "Upload and preview"
  end

  test "renders mapping and authorized progress" do
    import = build_import
    import.update!(requester: @actor)
    TabularImporter::PreparePreview.call(import)

    get "/imports/#{import.id}"
    assert_response :success
    assert_includes response.body, "Match columns"
    assert_includes response.body, "Ada"

    get "/imports/#{import.id}/progress", as: :json
    assert_response :success
    assert_equal "mapping_required", response.parsed_body["status"]
  end

  test "forbids access to another actor's import" do
    import = build_import
    import.update!(requester: TestActor.create!(name: "Someone else"))

    get "/imports/#{import.id}"
    assert_response :forbidden
  end
end
