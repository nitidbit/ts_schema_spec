# frozen_string_literal: true

require "fileutils"

require_relative "../ts_schema_spec"

module TsSchemaSpec
  # The skill is instructions an agent follows to write these specs, so a
  # silently outdated copy teaches the wrong API. The copy carries the gem
  # version and `check!` fails when the two diverge.
  module Skill
    NAME = "react-prop-type-spec"
    INSTALL_PATH = ".claude/skills/#{NAME}/SKILL.md"
    SOURCE_PATH = File.expand_path("../../skills/#{NAME}/SKILL.md", __dir__)
    STAMP = "ts_schema_spec_version"

    class << self
      def install(root = Dir.pwd)
        destination = File.join(root, INSTALL_PATH)
        FileUtils.mkdir_p(File.dirname(destination))
        File.write(destination, stamped(File.read(SOURCE_PATH)))
        destination
      end

      def installed_version(root = Dir.pwd)
        contents = File.read(File.join(root, INSTALL_PATH))
        contents[/^#{STAMP}: (.+)$/, 1]
      rescue Errno::ENOENT
        nil
      end

      def check!(root = Dir.pwd)
        found = installed_version(root)
        return true if found == TsSchemaSpec::VERSION

        raise Error, <<~MSG
          The #{NAME} skill in #{INSTALL_PATH} is #{found ? "stale (#{found})" : "not installed"};
          the gem is #{TsSchemaSpec::VERSION}.

          Run: bundle exec rake ts_schema_spec:install_skill
        MSG
      end

      private

      def stamped(contents)
        body = contents.sub(/^#{STAMP}: .*\n/, "")
        stamped = body.sub(/\A---\n/, "---\n#{STAMP}: #{TsSchemaSpec::VERSION}\n")

        if stamped == body
          raise Error, "#{SOURCE_PATH} does not open with YAML frontmatter, so the version stamp check! reads has nowhere to go."
        end

        stamped
      end
    end
  end
end
