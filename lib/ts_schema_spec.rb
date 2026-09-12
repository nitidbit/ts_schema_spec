# frozen_string_literal: true

require "json_schemer"

require_relative "ts_schema_spec/version"
require_relative "ts_schema_spec/generator"

require_relative "ts_schema_spec/railtie" if defined?(Rails::Railtie)

module TsSchemaSpec
  class Error < StandardError; end
  class GenerationError < Error; end

  class << self
    def schema_for(source, type)
      document = document_for(source)

      unless document.fetch("definitions", {}).key?(type)
        raise GenerationError, <<~MSG
          #{source} does not define #{type.inspect}.

          Generated definitions: #{document.fetch("definitions", {}).keys.sort.join(", ")}

          Is it exported?
        MSG
      end

      JSONSchemer.schema(document).ref("#/definitions/#{type}")
    end

    def clear_cache!
      documents.clear
    end

    private

    def document_for(source)
      documents[File.expand_path(source.to_s)] ||= Generator.generate(source)
    end

    def documents
      @documents ||= {}
    end
  end
end
