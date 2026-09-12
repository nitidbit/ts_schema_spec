# frozen_string_literal: true

# The gem does not vendor ts-json-schema-generator; it pins a range and asserts
# the output shape `schema_for` depends on. This spec is what fails when an
# upgrade changes that shape.
RSpec.describe TsSchemaSpec::Generator do
  before(:all) { @document = described_class.generate(File.expand_path("../fixtures/roleMatrix.ts", __dir__)) }

  subject(:document) { @document }

  it "puts exported types under a top-level definitions object" do
    expect(document["definitions"].keys).to include("RoleMatrixProps", "Role")
  end

  it "omits unexported types" do
    expect(document["definitions"].keys).to_not include("NotExported")
  end

  it "emits draft-07, which json_schemer resolves #/definitions refs against" do
    expect(document["$schema"]).to eq("http://json-schema.org/draft-07/schema#")
  end

  it "cross-references sibling types as #/definitions pointers" do
    expect(document.dig("definitions", "RoleMatrixProps", "properties", "roles", "items"))
      .to eq("$ref" => "#/definitions/Role")
  end

  it "closes objects to undeclared keys by default" do
    expect(document.dig("definitions", "Role", "additionalProperties")).to be(false)
  end
end
