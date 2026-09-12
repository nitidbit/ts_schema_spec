# frozen_string_literal: true

namespace :ts_schema_spec do
  desc "Copy the react-prop-type-spec agent skill into .claude/skills"
  task :install_skill do
    require "ts_schema_spec/skill"

    destination = TsSchemaSpec::Skill.install(defined?(Rails) ? Rails.root.to_s : Dir.pwd)
    puts "Installed #{TsSchemaSpec::Skill::NAME} v#{TsSchemaSpec::VERSION} to #{destination}"
    puts "Commit it — Claude Code reads skills from the working tree."
  end
end
