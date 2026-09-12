# frozen_string_literal: true

RSpec.describe "TsSchemaSpec.schema_for" do
  before { TsSchemaSpec.clear_cache! }

  it "validates a payload against the named type" do
    schema = TsSchemaSpec.schema_for(fixture("roleMatrix.ts"), "RoleMatrixProps")

    payload = {
      "roles" => [{ "id" => 1, "name" => "Nurse", "shortcode" => nil }],
      "assignedEntity" => "account",
      "reviewMode" => false,
    }

    expect(schema.valid?(payload)).to be(true)
  end

  it "is scoped to the named type, not the whole document" do
    schema = TsSchemaSpec.schema_for(fixture("roleMatrix.ts"), "RoleMatrixProps")

    expect(schema.valid?({ "nonsense" => true })).to be(false)
  end

  it "reports the failing pointer and constraint" do
    schema = TsSchemaSpec.schema_for(fixture("roleMatrix.ts"), "Role")

    errors = schema.validate({ "id" => "1", "name" => "Nurse", "shortcode" => nil }).to_a

    expect(errors.first["data_pointer"]).to eq("/id")
  end

  it "raises when the type is not in the generated document" do
    expect {
      TsSchemaSpec.schema_for(fixture("roleMatrix.ts"), "NotExported")
    }.to raise_error(TsSchemaSpec::GenerationError, /NotExported.*exported\?/m)
  end

  it "raises when the source file does not exist" do
    expect {
      TsSchemaSpec.schema_for(fixture("nope.ts"), "RoleMatrixProps")
    }.to raise_error(TsSchemaSpec::GenerationError)
  end

  it "generates once per file, not once per type" do
    allow(TsSchemaSpec::Generator).to receive(:generate).and_call_original

    TsSchemaSpec.schema_for(fixture("roleMatrix.ts"), "RoleMatrixProps")
    TsSchemaSpec.schema_for(fixture("roleMatrix.ts"), "Role")

    expect(TsSchemaSpec::Generator).to have_received(:generate).once
  end
end
