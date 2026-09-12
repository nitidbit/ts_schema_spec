# frozen_string_literal: true

require "rails/railtie"

module TsSchemaSpec
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/ts_schema_spec.rake", __dir__)
    end
  end
end
