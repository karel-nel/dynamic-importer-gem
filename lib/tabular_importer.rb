require "rails"
require "active_storage/engine"
require "active_job/railtie"
require "roo"
require "csv"
require "set"
require "securerandom"
require "zip"

require "tabular_importer/version"
require "tabular_importer/errors"
require "tabular_importer/column"
require "tabular_importer/definition"
require "tabular_importer/configuration"
require "tabular_importer/engine"

module TabularImporter
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def register(key, **options, &block)
      configuration.register(key, **options, &block)
    end

    def definition(key)
      configuration.fetch(key)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
