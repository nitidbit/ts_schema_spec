# frozen_string_literal: true

require "json"
require "open3"

module TsSchemaSpec
  module Generator
    COMMAND = %w[npx ts-json-schema-generator].freeze

    class << self
      def generate(source)
        command = command_for(source)
        stdout, stderr, status = Open3.capture3(*command)

        unless status.success?
          raise GenerationError, failure(command, stderr)
        end

        JSON.parse(stdout)
      rescue JSON::ParserError => e
        raise GenerationError, failure(command, "#{e.message}\n\n#{stderr}")
      rescue Errno::ENOENT
        raise GenerationError, missing_generator(command)
      end

      def command_for(source)
        COMMAND + ["--path", source.to_s, "--no-type-check"] + TsSchemaSpec.config.to_args
      end

      private

      # npx's own phrasing for "the package is not installed". Anything looser
      # — a bare "not found" — swallows the generator's real diagnostic.
      MISSING_PACKAGE = /missing packages|could not determine executable|npx.*not found|not found.*npx/i

      def missing_generator(command, stderr = nil)
        message = <<~MSG
          could not run #{COMMAND.join(" ")}.

          The generator parses your app's TypeScript, so it resolves from your
          node_modules rather than from the gem:

            npm install --save-dev ts-json-schema-generator

          Rerun: #{command.join(" ")}
        MSG
        return message if stderr.to_s.strip.empty?

        "#{message}\n#{stderr.strip}\n"
      end

      def failure(command, stderr)
        return missing_generator(command, stderr) if stderr.to_s.match?(MISSING_PACKAGE)

        <<~MSG
          ts-json-schema-generator failed.

          Rerun: #{command.join(" ")}

          #{stderr.strip}
        MSG
      end
    end
  end
end
