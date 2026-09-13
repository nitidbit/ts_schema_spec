# frozen_string_literal: true

require "json_schemer"

require_relative "ts_schema_spec/version"
require_relative "ts_schema_spec/config"
require_relative "ts_schema_spec/generator"

require_relative "ts_schema_spec/railtie" if defined?(Rails::Railtie)

module TsSchemaSpec
  class Error < StandardError; end
  class GenerationError < Error; end

  class << self
    def schema_for(source, type)
      validate_arguments!(source, type)
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

    def config
      @config ||= Config.new
    end

    def configure
      yield(config)
      clear_cache!
    end

    def reset_config!
      @config = nil
      clear_cache!
    end

    private

    PATH_LIKE = %r{/|\.tsx?\z}

    def validate_arguments!(source, type)
      raise ArgumentError, "expects a path and a type name, e.g. schema_for(\"app/javascript/Foo.tsx\", \"FooProps\")" if type.nil?

      return unless type.to_s.match?(PATH_LIKE) && !source.to_s.match?(PATH_LIKE)

      raise ArgumentError, <<~MSG
        the arguments look reversed: #{source.inspect} was given as the source
        file and #{type.inspect} as the type name. Expected (path, type).
      MSG
    end

    def document_for(source)
      documents[[File.expand_path(source.to_s), config.to_args]] ||= Generator.generate(source)
    end

    def documents
      @documents ||= {}
    end
  end
end
