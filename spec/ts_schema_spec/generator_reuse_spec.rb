# frozen_string_literal: true

require "tmpdir"

RSpec.describe TsSchemaSpec::Generator, "across many sources" do
  around do |example|
    described_class.stop
    example.run
    described_class.stop
  end

  let(:sources) { [fixture("roleMatrix.ts"), fixture("aliased/widget.ts")] }

  it "generates what the generator's own CLI does" do
    sources.each do |source|
      cli, = Open3.capture2(*described_class.command_for(source))

      expect(described_class.generate(source)).to eq(JSON.parse(cli))
    end
  end

  it "starts node once, however many sources it reads" do
    allow(Open3).to receive(:popen3).and_call_original

    sources.each { |source| described_class.generate(source) }

    expect(Open3).to have_received(:popen3).once
  end

  it "keeps replies in step after a request is interrupted" do
    expect { Timeout.timeout(0.01) { described_class.generate(fixture("roleMatrix.ts")) } }
      .to raise_error(Timeout::Error)

    expect(described_class.generate(fixture("aliased/widget.ts"))["definitions"]).to include("AliasedWidgetProps")
  end

  it "starts a new server when the old one has died" do
    waits = []
    allow(Open3).to receive(:popen3).and_wrap_original { |original, *args| original.call(*args).tap { |io| waits << io.last } }
    described_class.generate(fixture("roleMatrix.ts"))

    Process.kill("KILL", waits.last.pid)
    waits.last.join

    expect(described_class.generate(fixture("roleMatrix.ts"))["definitions"]).to include("Role")
  end

  it "uses the current directory's node_modules, not those of the directory node started in" do
    described_class.generate(fixture("roleMatrix.ts"))

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        expect { described_class.generate("anything.ts") }
          .to raise_error(TsSchemaSpec::GenerationError, /npm install --save-dev ts-json-schema-generator/)
      end
    end
  end

  it "sees a file created after the compiler first looked for it" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/a.ts", "import { Shared } from './shared'\nexport interface A { shared: Shared }\n")
      File.write("#{dir}/b.ts", "import { Shared } from './shared'\nexport interface B { shared: Shared }\n")
      described_class.generate("#{dir}/a.ts")

      File.write("#{dir}/shared.ts", "export interface Shared { name: string }\n")

      expect(described_class.generate("#{dir}/b.ts").dig("definitions", "Shared", "required")).to eq(["name"])
    end
  end

  it "resolves relative paths against the current directory, not the one node started in" do
    described_class.generate(fixture("roleMatrix.ts"))

    Dir.chdir(fixture("")) do
      expect(described_class.generate("roleMatrix.ts")["definitions"]).to include("Role")
    end
  end
end
