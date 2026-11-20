# frozen_string_literal: true

require "tmpdir"

RSpec.describe TsSchemaSpec::Generator do
  around do |example|
    described_class.stop
    example.run
    described_class.stop
  end

  it "explains how to install the generator when node is not on PATH" do
    allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, "node")

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /npm install --save-dev ts-json-schema-generator/)
  end

  context "in a project without the generator in its node_modules" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    it "explains how to install it" do
      expect { described_class.generate("anything.ts") }
        .to raise_error(TsSchemaSpec::GenerationError, /npm install --save-dev ts-json-schema-generator/)
    end

    it "keeps node's own complaint alongside the instructions" do
      expect { described_class.generate("anything.ts") }
        .to raise_error(TsSchemaSpec::GenerationError, /Cannot find module/)
    end
  end

  it "keeps the generator's own stderr when it fails" do
    expect { described_class.generate(fixture("missing.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /No input files/)
  end

  it "names a command that reproduces the failure" do
    expect { described_class.generate(fixture("missing.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /Rerun: npx ts-json-schema-generator --path \S+missing\.ts/)
  end

  it "says how node ended when it dies without a word on stderr" do
    waits = []
    allow(Open3).to receive(:popen3).and_wrap_original { |original, *args| original.call(*args).tap { |io| waits << io.last } }
    allow(described_class).to receive(:exchange).and_wrap_original do |original, *args|
      Process.kill("KILL", waits.last.pid)
      waits.last.join
      original.call(*args)
    end

    expect { described_class.generate(fixture("roleMatrix.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /node ended: .*SIGKILL/)
  end

  it "still generates after a failure" do
    expect { described_class.generate(fixture("missing.ts")) }.to raise_error(TsSchemaSpec::GenerationError)

    expect(described_class.generate(fixture("roleMatrix.ts"))["definitions"]).to include("Role")
  end
end
