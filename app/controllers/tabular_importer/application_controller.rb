module TabularImporter
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    layout "tabular_importer/application"

    before_action :authenticate_actor!
    helper_method :current_import_actor

    rescue_from TabularImporter::UnknownImportType, with: :render_not_found
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    private

    def authenticate_actor!
      TabularImporter.configuration.authenticate.call(self)
    end

    def current_import_actor
      @current_import_actor ||= TabularImporter.configuration.current_actor.call(self)
    end

    def authorize_import!(import, action)
      allowed = TabularImporter.configuration.authorize.call(current_import_actor, import, action)
      raise TabularImporter::Unauthorized unless allowed
    rescue TabularImporter::Unauthorized
      head :forbidden
    end

    def render_not_found
      head :not_found
    end
  end
end
