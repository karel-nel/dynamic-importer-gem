module TabularImporter
  class Error < StandardError; end
  class UnknownImportType < Error; end
  class InvalidMapping < Error
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end
  class UnsupportedFile < Error; end
  class ResourceLimitExceeded < UnsupportedFile; end
  class ProcessingLeaseUnavailable < Error; end
  class InvalidState < Error; end
  class Unauthorized < Error; end
end
