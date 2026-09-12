# frozen_string_literal: true

RSpec.describe "TsSchemaSpec.configure" do
  after { TsSchemaSpec.reset_config! }

  def aliased(name)
    File.expand_path("../fixtures/aliased/#{name}", __dir__)
  end

  it "passes --tsconfig to the generator when configured" do
    TsSchemaSpec.configure { |c| c.tsconfig = aliased("tsconfig.json") }

    expect(TsSchemaSpec::Generator.command_for("widget.ts"))
      .to include("--tsconfig", aliased("tsconfig.json"))
  end

  it "passes arbitrary extra arguments through" do
    TsSchemaSpec.configure { |c| c.generator_args = ["--strict-tuples"] }

    expect(TsSchemaSpec::Generator.command_for("widget.ts")).to include("--strict-tuples")
  end

  it "resolves a path-aliased import when tsconfig is set" do
    TsSchemaSpec.configure { |c| c.tsconfig = aliased("tsconfig.json") }

    schema = TsSchemaSpec.schema_for(aliased("widget.ts"), "AliasedWidgetProps")

    expect(schema.valid?({ "label" => "x", "role" => { "id" => 1, "name" => "Nurse" } })).to be(true)
    expect(schema.valid?({ "label" => "x", "role" => "not a role" })).to be(false)
  end

  it "leaves the aliased type unconstrained without tsconfig" do
    schema = TsSchemaSpec.schema_for(aliased("widget.ts"), "AliasedWidgetProps")

    expect(schema.valid?({ "label" => "x", "role" => "not a role" })).to be(true)
  end

  it "clears the schema cache so a config change takes effect" do
    TsSchemaSpec.schema_for(aliased("widget.ts"), "AliasedWidgetProps")

    expect { TsSchemaSpec.configure { |c| c.tsconfig = aliased("tsconfig.json") } }
      .to change { TsSchemaSpec.schema_for(aliased("widget.ts"), "AliasedWidgetProps").valid?({ "label" => "x", "role" => 1 }) }
      .from(true).to(false)
  end
end
