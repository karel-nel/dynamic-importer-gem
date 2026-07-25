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

  test "renders a required confirmation checkbox only for allowed partial imports" do
    register_invalid_type(:strict_rows, allow_partial_imports: false)
    strict = ready_invalid_import("strict_rows")
    get "/imports/#{strict.id}"
    assert_response :success
    assert_includes response.body, "Processing blocked"
    refute_includes response.body, "confirm_partial_import"

    register_invalid_type(:partial_rows, allow_partial_imports: true)
    partial = ready_invalid_import("partial_rows")
    get "/imports/#{partial.id}"
    assert_response :success
    assert_includes response.body, "confirm_partial_import"
    assert_includes response.body, "required=\"required\""

    post "/imports/#{partial.id}/process"
    assert_redirected_to "/imports/#{partial.id}"
    assert_equal "ready", partial.reload.status

    post "/imports/#{partial.id}/process", params: { confirm_partial_import: "1" }
    assert_redirected_to "/imports/#{partial.id}"
    assert_equal "processing", partial.reload.status
    assert partial.partial_import_confirmed?
  end

  private

  def register_invalid_type(key, allow_partial_imports:)
    analyzer = Class.new do
      def self.call(import:, rows:, progress:)
        { total_rows: rows.count, valid_rows: 1, invalid_rows: 1 }
      end
    end
    TabularImporter.register key,
      columns: [{ key: :external_id, required: true, aliases: ["CSA ID"] }],
      analyzer:,
      processor: TestProcessor,
      allow_partial_imports:
  end

  def ready_invalid_import(import_type)
    import = build_import(import_type:)
    import.update!(requester: @actor)
    TabularImporter::PreparePreview.call(import)
    import.transition_to!(:ready, analysis: { invalid_rows: 1, valid_rows: 1, invalid_source_rows: [2] })
    import
  end
end
