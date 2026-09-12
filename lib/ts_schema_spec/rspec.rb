# frozen_string_literal: true

require "json"
require "rspec/expectations"

require_relative "../ts_schema_spec"

RSpec::Matchers.define :match_schema do |schema|
  match do |actual|
    @errors = schema.validate(actual).to_a
    @errors.empty?
  end

  failure_message do |actual|
    details = @errors.map do |error|
      pointer = error["data_pointer"]
      pointer = "(root)" if pointer.nil? || pointer.empty?
      " - #{pointer}: #{error["error"]}"
    end

    <<~MSG
      expected the payload to match the schema, but:
      #{details.join("\n")}

      Payload was:
      #{JSON.pretty_generate(actual)}
    MSG
  end

  failure_message_when_negated do |actual|
    "expected the payload not to match the schema, but it did:\n#{JSON.pretty_generate(actual)}"
  end
end
