# frozen_string_literal: true

RSpec.describe TsSchemaSpec::Generator do
  it "explains how to install the generator when npx is not on PATH" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "npx")

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /npm install --save-dev ts-json-schema-generator/)
  end

  it "explains the same when npx cannot find the package" do
    allow(Open3).to receive(:capture3)
      .and_return(["", "npm error npx canceled due to missing packages", instance_double(Process::Status, success?: false)])

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /npm install --save-dev ts-json-schema-generator/)
  end
end
