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

    BRANCHES = %w[anyOf oneOf allOf].freeze

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

      def empty?(errors)
        errors == [EMPTY]
      end

      private

      def collection?(schema, actual)
        actual.is_a?(Array) && !describes_array?(schema)
      end

      # A type can reach "array" through a union or an alias, so the literal
      # `"type"` of the schema is not enough: `Role[] | null` and
      # `type Roles = RoleList` both describe an array without saying so here.
      def describes_array?(schema, value = schema.value, seen = [])
        return false unless value.is_a?(Hash)

        if (pointer = value["$ref"])
          return false if seen.include?(pointer)

          return describes_array?(schema, resolve(schema, pointer), seen + [pointer])
        end

        return true if Array(value["type"]).include?("array")

        BRANCHES.any? do |branch|
          Array(value[branch]).any? { |option| describes_array?(schema, option, seen) }
        end
      end

      def resolve(schema, pointer)
        schema.ref(pointer).value
      rescue StandardError
        nil
      end
    end
  end
end

RSpec::Matchers.define :match_schema do |source, type|
  def validation_errors(actual, source, type)
    schema = TsSchemaSpec.schema_for(source, type)
    @errors = TsSchemaSpec::Matching.errors(schema, actual)
  end

  # Worded for both directions: this message is what an empty collection gets
  # whichever way the assertion was written.
  def empty_collection_message
    <<~MSG
      expected a non-empty collection, but it was empty, so nothing was
      validated.

      Usually the component was not rendered on the page, or no records
      existed for the endpoint to serialize. If an empty result is what you
      meant to assert, use `be_empty` or `eq([])` — match_schema on an empty
      collection checks nothing.
    MSG
  end

  match do |actual|
    validation_errors(actual, source, type).empty?
  end

  # An empty collection fails either way round: negating the matcher would
  # otherwise turn the vacuous pass back on.
  match_when_negated do |actual|
    errors = validation_errors(actual, source, type)
    errors.any? && !TsSchemaSpec::Matching.empty?(errors)
  end

  failure_message do |actual|
    next empty_collection_message if TsSchemaSpec::Matching.empty?(@errors)

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
    next empty_collection_message if TsSchemaSpec::Matching.empty?(@errors)

    "expected the payload not to match #{type} (#{source}), but it did:\n#{JSON.pretty_generate(actual)}"
  end
end
