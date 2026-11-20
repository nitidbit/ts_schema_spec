# frozen_string_literal: true

require "tmpdir"

RSpec.describe "TsSchemaSpec.schema_for" do
  before { TsSchemaSpec.clear_cache! }

  it "reads an edited source again after clear_cache!" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/edited.ts", "export interface Edited { x: string }\n")
      TsSchemaSpec.schema_for("#{dir}/edited.ts", "Edited")

      File.write("#{dir}/edited.ts", "export interface Edited { x: number }\n")
      TsSchemaSpec.clear_cache!

      expect(TsSchemaSpec.schema_for("#{dir}/edited.ts", "Edited").valid?({ "x" => 1 })).to be(true)
    end
  end

  it "reads an edited source again after configure" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/configured.ts", "export interface Configured { x: string }\n")
      TsSchemaSpec.schema_for("#{dir}/configured.ts", "Configured")

      File.write("#{dir}/configured.ts", "export interface Configured { x: number }\n")
      TsSchemaSpec.configure { |c| c.generator_args = [] }

      expect(TsSchemaSpec.schema_for("#{dir}/configured.ts", "Configured").valid?({ "x" => 1 })).to be(true)
    end
  end

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
