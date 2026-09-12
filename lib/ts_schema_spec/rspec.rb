# frozen_string_literal: true

require "json"
require "rspec/expectations"

require_relative "../ts_schema_spec"

module TsSchemaSpec
  # A payload is often a collection — every mount of a component on the page,
  # every record in an index response. Validating each item against an object
  # schema is the common case, so the matcher handles it rather than leaving
  # callers to reach for `all`, which passes vacuously on an empty collection
  # and so silently asserts nothing.
  module Matching
    EMPTY = :empty_collection

    class << self
      def errors(schema, actual)
        return schema.validate(actual).to_a unless collection?(schema, actual)
        return [EMPTY] if actual.empty?

        actual.each_with_index.flat_map do |item, index|
          schema.validate(item).to_a.map do |error|
            error.merge("data_pointer" => "/#{index}#{error["data_pointer"]}")
          end
        end
      end

      private

      def collection?(schema, actual)
        actual.is_a?(Array) && !describes_array?(schema)
      end

      def describes_array?(schema)
        type = schema.value["type"]
        type == "array" || (type.is_a?(Array) && type.include?("array"))
      end
    end
  end
end

RSpec::Matchers.define :match_schema do |source, type|
  match do |actual|
    schema = TsSchemaSpec.schema_for(source, type)
    @errors = TsSchemaSpec::Matching.errors(schema, actual)
    @errors.empty?
  end

  failure_message do |actual|
    if @errors == [TsSchemaSpec::Matching::EMPTY]
      next <<~MSG
        expected a non-empty collection to match the schema, but it was empty,
        so nothing was validated.

        Usually the component was not rendered on the page, or no records
        existed for the endpoint to serialize. If an empty result is what you
        meant to assert, use `be_empty` or `eq([])` — match_schema on an empty
        collection checks nothing.
      MSG
    end

    details = @errors.map do |error|
      pointer = error["data_pointer"]
      pointer = "(root)" if pointer.nil? || pointer.empty?
      " - #{pointer}: #{error["error"]}"
    end

    <<~MSG
      expected the payload to match #{type} (#{source}), but:
      #{details.join("\n")}

      Payload was:
      #{JSON.pretty_generate(actual)}
    MSG
  end

  failure_message_when_negated do |actual|
    "expected the payload not to match #{type} (#{source}), but it did:\n#{JSON.pretty_generate(actual)}"
  end
end
