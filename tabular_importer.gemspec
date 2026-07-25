require_relative "lib/tabular_importer/version"

Gem::Specification.new do |spec|
  spec.name = "tabular_importer"
  spec.version = TabularImporter::VERSION
  spec.authors = ["PCD"]
  spec.summary = "A configurable, staged CSV and XLSX import engine for Rails"
  spec.description = "Upload, preview, map, analyse, process, and monitor tabular imports through a mountable Rails engine."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,lib}/**/*", "LICENSE.txt", "README.md"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.0", "< 9.0"
  spec.add_dependency "roo", "~> 2.10"
  spec.add_dependency "csv", "~> 3.2"
end
