module TabularImporter
  class ImportsController < ApplicationController
    before_action :set_import, only: %i[show update_mapping start_processing retry_import progress]

    def index
      @imports = TabularImporter.configuration.scope
        .call(Import.all, current_import_actor)
        .recent_first
        .limit(100)
      @back_url = configured_back_url
    end

    def new
      @definition = TabularImporter.definition(params.require(:import_type))
      @import = Import.new(import_type: @definition.key)
      @importable_sgid = params[:importable_sgid]
    end

    def create
      @definition = TabularImporter.definition(import_params[:import_type])
      @import = Import.new(import_params.except(:importable_sgid))
      @import.requester = current_import_actor if current_import_actor.is_a?(ActiveRecord::Base)
      @import.importable = locate_importable(import_params[:importable_sgid])

      if @import.save
        PreparePreview.call(@import)
        redirect_to import_path(@import)
      else
        render :new, status: :unprocessable_entity
      end
    rescue UnsupportedFile => error
      @import.fail!(error, stage: "preview") if @import&.persisted?
      redirect_to import_path(@import)
    end

    def show
      @definition = @import.definition
      @presented_result = @definition.presenter.call(import: @import).to_h if @import.completed? && @definition.presenter
    end

    def update_mapping
      mapping = MappingValidator.call(
        definition: @import.definition,
        headers: @import.source_headers,
        mapping: mapping_params
      )
      @import.transition_to!(:analyzing, column_mapping: mapping, analysis: {}, result_summary: {})
      AnalyzeJob.perform_later(@import)
      redirect_to import_path(@import)
    rescue InvalidMapping => error
      @mapping_errors = error.errors
      @definition = @import.definition
      render :show, status: :unprocessable_entity
    end

    def start_processing
      confirmed = ActiveModel::Type::Boolean.new.cast(params[:confirm_partial_import])
      @import.begin_processing!(partial_import_confirmed: confirmed)
      ProcessJob.perform_later(@import)
      redirect_to import_path(@import)
    rescue InvalidState => error
      redirect_to import_path(@import), alert: error.message
    end

    def retry_import
      raise InvalidState, "Only failed imports can be retried" unless @import.failed?

      if @import.failure_stage == "processing"
        @import.transition_to!(:processing, error_class: nil, error_message: nil,
          processor_execution_id: nil, processor_execution_started_at: nil, processor_heartbeat_at: nil)
        ProcessJob.perform_later(@import)
      elsif @import.failure_stage == "preview"
        PreparePreview.call(@import)
      else
        @import.transition_to!(:analyzing, error_class: nil, error_message: nil)
        AnalyzeJob.perform_later(@import)
      end
      redirect_to import_path(@import)
    rescue InvalidState => error
      redirect_to import_path(@import), alert: error.message
    end

    def progress
      render json: {
        status: @import.status,
        current: @import.progress_current,
        total: @import.progress_total,
        message: @import.progress_message,
        terminal: @import.terminal?
      }
    end

    private

    def set_import
      @import = Import.find(params[:id])
      authorize_import!(@import, action_name.to_sym)
    end

    def import_params
      params.require(:import).permit(:import_type, :source_file, :importable_sgid, metadata: {})
    end

    def mapping_params
      params.fetch(:column_mapping, {}).permit!.to_h
    end

    def configured_back_url
      urls = TabularImporter.configuration.definitions.values.filter_map do |definition|
        definition.back_url_for(self).presence
      end
      urls.uniq.one? ? urls.first : nil
    end

    def locate_importable(sgid)
      return if sgid.blank?
      record = GlobalID::Locator.locate_signed(sgid, for: "tabular_importer")
      raise ActiveRecord::RecordNotFound, "Invalid or expired import context" unless record
      record
    end
  end
end
