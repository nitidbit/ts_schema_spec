# frozen_string_literal: true

require_relative "lib/ts_schema_spec/version"

Gem::Specification.new do |spec|
  spec.name = "ts_schema_spec"
  spec.version = TsSchemaSpec::VERSION
  spec.authors = ["Vernon Coffey"]
  spec.email = ["vccoffey@gmail.com"]

  spec.summary = "Assert that a Rails payload matches the TypeScript type the React side consumes."
  spec.homepage = "https://github.com/nitidbit/ts_schema_spec"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.{rb,rake}", "skills/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json_schemer", ">= 2.0", "< 3.0"
  spec.add_dependency "nokogiri", ">= 1.10"
end
