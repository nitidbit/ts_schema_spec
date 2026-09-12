# frozen_string_literal: true

require "ts_schema_spec"

module FixturePath
  def fixture(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end

RSpec.configure do |config|
  config.include FixturePath

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
