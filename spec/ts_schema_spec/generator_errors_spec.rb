# frozen_string_literal: true

require "tmpdir"

RSpec.describe TsSchemaSpec::Generator do
  around do |example|
    described_class.stop
    example.run
    described_class.stop
  end

  it "says node is missing, rather than the generator, when node is not on PATH" do
    allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, "node")

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /could not run node.*PATH/m) { |e| expect(e.message).not_to include("npm install") }
  end

  it "reports an error that isn't about node itself as it is, with the command that reproduces it" do
    allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, "/gone")

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, %r{/gone}) { |e| expect(e.message).to include("Rerun:").and(satisfy { |m| !m.include?("PATH") }) }
  end

  context "in a project without the generator in its node_modules" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    it "explains how to install it" do
      expect { described_class.generate("anything.ts") }
        .to raise_error(TsSchemaSpec::GenerationError, /npm install --save-dev ts-json-schema-generator/)
    end

    it "says the generator could not be loaded, not that npx could not run" do
      expect { described_class.generate("anything.ts") }
        .to raise_error(TsSchemaSpec::GenerationError, /\Acould not load ts-json-schema-generator from your node_modules/)
    end

    it "keeps node's own complaint alongside the instructions" do
      expect { described_class.generate("anything.ts") }
        .to raise_error(TsSchemaSpec::GenerationError, /Cannot find module/)
    end
  end

  context "in a project with a generator older than 2.4" do
    around do |example|
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p("#{dir}/node_modules/ts-json-schema-generator/dist")
        File.write("#{dir}/node_modules/ts-json-schema-generator/package.json", '{"version": "2.3.0"}')
        File.write("#{dir}/node_modules/ts-json-schema-generator/dist/ts-json-schema-generator.js", "")
        Dir.chdir(dir) { example.run }
      end
    end

    it "names the versions it supports" do
      expect { described_class.generate("anything.ts") }
        .to raise_error(TsSchemaSpec::GenerationError, /\Ats_schema_spec supports .*2\.4 or later.*2\.3\.0/m) { |e| expect(e.message).not_to include("Rerun") }
    end
  end

  it "keeps the whole failure when the version requirement is only quoted in it" do
    allow(described_class).to receive(:request).and_return(
      "status" => 1, "stdout" => "",
      "stderr" => "wrapped: ts_schema_spec supports ts-json-schema-generator 2.4 or later 2.x\nmore detail"
    )

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /Rerun:.*more detail/m)
  end

  it "keeps the generator's own stderr when it fails" do
    expect { described_class.generate(fixture("missing.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /No input files/)
  end

  it "keeps the generator's own stderr when a module it can't find merely starts like a package it needs" do
    allow(described_class).to receive(:request)
      .and_return("status" => 1, "stdout" => "", "stderr" => "Error: Cannot find module 'typescript-plugin-x'")

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /typescript-plugin-x/) { |e| expect(e.message).not_to include("npm install") }
  end

  it "keeps TypeScript's own complaint about a module it can't resolve" do
    allow(described_class).to receive(:request).and_return(
      "status" => 1, "stdout" => "",
      "stderr" => "error TS2307: Cannot find module 'typescript' or its corresponding type declarations."
    )

    expect { described_class.generate("anything.ts") }
      .to raise_error(TsSchemaSpec::GenerationError, /TS2307/) { |e| expect(e.message).not_to include("npm install") }
  end

  it "leaves out the stack trace the CLI writes to stdout" do
    expect { described_class.generate(fixture("missing.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError) { |e| expect(e.message).not_to match(/^\s+at /) }
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

  it "shows what node wrote when it isn't a reply" do
    TsSchemaSpec.configure { |c| c.generator_args = ["--version"] }

    expect { described_class.generate(fixture("roleMatrix.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /not a reply: \d+\.\d+\.\d+/)
  ensure
    TsSchemaSpec.reset_config!
  end

  it "shows what node wrote when it is JSON but not a reply" do
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args|
      original.call(*args).tap { |io| allow(io[1]).to receive(:gets).and_return("2\n") }
    end

    expect { described_class.generate(fixture("roleMatrix.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /not a reply: 2$/)
  end

  it "shows what node wrote even when it isn't valid UTF-8" do
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args|
      original.call(*args).tap { |io| allow(io[1]).to receive(:gets).and_return((+"\xFF\n").force_encoding("UTF-8")) }
    end

    expect { described_class.generate(fixture("roleMatrix.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /not a reply/)
  end

  it "says when ts_schema_spec stopped node itself" do
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args|
      original.call(*args).tap { |io| allow(io[1]).to receive(:gets).and_return("2\n") }
    end

    expect { described_class.generate(fixture("roleMatrix.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError, /after ts_schema_spec sent it TERM/)
  end

  it "lets node exit by itself once its stdout ends, without a signal" do
    allow(Process).to receive(:kill).and_call_original
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args|
      original.call(*args).tap { |io| allow(io[1]).to receive(:gets).and_return(nil) }
    end

    expect { described_class.generate(fixture("roleMatrix.ts")) }
      .to raise_error(TsSchemaSpec::GenerationError) { |e| expect(e.message).not_to include("sent it") }
    expect(Process).not_to have_received(:kill)
  end

  it "still generates after a failure" do
    expect { described_class.generate(fixture("missing.ts")) }.to raise_error(TsSchemaSpec::GenerationError)

    expect(described_class.generate(fixture("roleMatrix.ts"))["definitions"]).to include("Role")
  end
end
