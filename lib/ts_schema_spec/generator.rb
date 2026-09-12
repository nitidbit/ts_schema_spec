# frozen_string_literal: true

require "json"
require "open3"

module TsSchemaSpec
  module Generator
    COMMAND = %w[npx ts-json-schema-generator].freeze

    class << self
      def generate(source)
        command = COMMAND + ["--path", source.to_s, "--no-type-check"]
        stdout, stderr, status = Open3.capture3(*command)

        unless status.success?
          raise GenerationError, failure(command, stderr)
        end

        JSON.parse(stdout)
      rescue JSON::ParserError => e
        raise GenerationError, failure(command, "#{e.message}\n\n#{stderr}")
      end

      private

      def failure(command, stderr)
        <<~MSG
          ts-json-schema-generator failed.

          Rerun: #{command.join(" ")}

          #{stderr.strip}
        MSG
      end
    end
  end
end
