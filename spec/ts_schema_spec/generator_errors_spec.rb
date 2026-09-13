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

  it "keeps the generator's own stderr when it merely mentions something not found" do
    allow(Open3).to receive(:capture3)
      .and_return(["", "error TS2307: Cannot find module '@/roles'. File not found.", instance_double(Process::Status, success?: false)])

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /Cannot find module/)
  end

  it "keeps the stderr alongside the install instructions when the package is missing" do
    allow(Open3).to receive(:capture3)
      .and_return(["", "npm error npx canceled due to missing packages", instance_double(Process::Status, success?: false)])

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /npx canceled/)
  end
end
