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

  it "does not signal a node it has already reaped, whose pid may now be another process's" do
    waits = []
    allow(Open3).to receive(:popen3).and_wrap_original { |original, *args| original.call(*args).tap { |io| waits << io.last } }
    allow(Process).to receive(:kill).and_call_original
    described_class.generate(fixture("roleMatrix.ts"))
    allow(described_class).to receive(:exchange) do
      Process.kill("KILL", waits.last.pid)
      waits.last.join
      raise Timeout::Error
    end

    expect { described_class.generate(fixture("roleMatrix.ts")) }.to raise_error(Timeout::Error)
    expect(Process).not_to have_received(:kill).with("TERM", waits.last.pid)
  end

  it "stops while a forked child still holds node's stdin open" do
    stub_const("TsSchemaSpec::Generator::EXIT_TIMEOUT", 0.1)
    described_class.generate(fixture("roleMatrix.ts"))
    child = fork do
      sleep 5
      exit!
    end

    expect { Timeout.timeout(2) { described_class.stop } }.not_to raise_error
  ensure
    if child
      Process.kill("KILL", child)
      Process.wait(child)
    end
  end

  it "kills a node that outlasts TERM" do
    stub_const("TsSchemaSpec::Generator::EXIT_TIMEOUT", 0.1)
    allow(Process).to receive(:kill).and_call_original
    allow(Process).to receive(:kill).with("TERM", anything)
    described_class.generate(fixture("roleMatrix.ts"))
    child = fork do
      sleep 5
      exit!
    end

    expect { Timeout.timeout(2) { described_class.stop } }.not_to raise_error
  ensure
    if child
      Process.kill("KILL", child)
      Process.wait(child)
    end
  end

  it "closes every pipe to a node it stops" do
    pipes = []
    allow(Open3).to receive(:popen3).and_wrap_original { |original, *args| original.call(*args).tap { |io| pipes.concat(io.first(3)) } }
    described_class.generate(fixture("roleMatrix.ts"))

    described_class.stop

    expect(pipes).to all(be_closed)
  end

  it "hands the generator a typescript with all of its own keys, which tslib's __importStar copies" do
    script = <<~JS
      require(#{described_class::SERVER.to_json})
      const path = require('node:path')
      const generatorDir = path.dirname(require.resolve('ts-json-schema-generator/package.json'))
      const ts = require(require.resolve('typescript', { paths: [generatorDir] }))
      process.stdout.write(JSON.stringify(Object.keys(ts)))
    JS

    out, = Open3.capture2("node", "-e", script, stdin_data: "")

    expect(JSON.parse(out)).to include("SyntaxKind", "createProgram", "parseJsonConfigFileContent")
  end

  it "generates under a tsconfig that extends a base TypeScript complains about, as the CLI does" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/base.json", '{"compilerOptions": {"bogus": 1}}')
      File.write("#{dir}/tsconfig.json", '{"extends": "./base.json"}')
      TsSchemaSpec.configure { |c| c.tsconfig = "#{dir}/tsconfig.json" }

      expect(described_class.generate(fixture("roleMatrix.ts"))["definitions"]).to include("Role")
    end
  ensure
    TsSchemaSpec.reset_config!
  end

  it "passes createProgram's object form through to typescript" do
    script = <<~JS
      require(#{described_class::SERVER.to_json})
      const path = require('node:path')
      const generatorDir = path.dirname(require.resolve('ts-json-schema-generator/package.json'))
      const ts = require(require.resolve('typescript', { paths: [generatorDir] }))
      process.stdout.write(String(ts.createProgram({ rootNames: [], options: {} }).getRootFileNames().length))
    JS

    out, = Open3.capture2("node", "-e", script, stdin_data: "")

    expect(out).to eq("0")
  end

  it "says nothing of how node ended in a forked child, which can't know" do
    described_class.generate(fixture("roleMatrix.ts"))
    reader, writer = IO.pipe
    child = fork do
      reader.close
      writer.write("stopped: #{described_class.stop}")
    ensure
      writer.close
      exit!
    end
    writer.close

    expect(reader.read).to start_with("stopped: ").and(satisfy { |out| !out.include?("node ended") })
  ensure
    reader&.close
    Process.wait(child) if child
  end

  it "leaves a referenced file that doesn't exist to TypeScript" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/refers.ts", "/// <reference path=\"./missing.d.ts\" />\nexport interface Refers { x: string }\n")

      expect(described_class.generate("#{dir}/refers.ts")["definitions"]).to include("Refers")
    end
  end

  it "sees an edit to a tsconfig that the configured one extends" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/x1.ts", "export interface X { one: string }\n")
      File.write("#{dir}/x2.ts", "export interface X { two: number }\n")
      File.write("#{dir}/a.ts", "import { X } from '@x'\nexport interface A { x: X }\n")
      File.write("#{dir}/b.ts", "import { X } from '@x'\nexport interface B { x: X }\n")
      File.write("#{dir}/base.json", '{"compilerOptions": {"paths": {"@x": ["./x1.ts"]}}}')
      File.write("#{dir}/tsconfig.json", '{"extends": "./base.json"}')
      TsSchemaSpec.configure { |c| c.tsconfig = "#{dir}/tsconfig.json" }
      described_class.generate("#{dir}/a.ts")

      File.write("#{dir}/base.json", '{"compilerOptions": {"paths": {"@x": ["./x2.ts"]}}}')

      expect(described_class.generate("#{dir}/b.ts").dig("definitions", "X", "properties").keys).to eq(["two"])
    end
  ensure
    TsSchemaSpec.reset_config!
  end

  it "resolves an import again once a closer match appears" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/shared")
      File.write("#{dir}/shared/index.ts", "export interface Shared { fromIndex: string }\n")
      File.write("#{dir}/a.ts", "import { Shared } from './shared'\nexport interface A { shared: Shared }\n")
      described_class.generate("#{dir}/a.ts")

      File.write("#{dir}/shared.ts", "export interface Shared { fromFile: number }\n")

      expect(described_class.generate("#{dir}/a.ts").dig("definitions", "Shared", "properties").keys).to eq(["fromFile"])
    end
  end

  it "generates from a path holding a line or paragraph separator" do
    Dir.mktmpdir do |dir|
      path = "#{dir}/odd\u2028name\u2029.ts"
      File.write(path, "export interface Odd { x: string }\n")

      expect(described_class.generate(path)["definitions"]).to include("Odd")
    end
  end

  it "sees a tsconfig package the configured one extends once it is installed" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/x2.ts", "export interface X { two: number }\n")
      File.write("#{dir}/a.ts", "import { X } from '@x'\nexport interface A { x: X }\n")
      File.write("#{dir}/b.ts", "import { X } from '@x'\nexport interface B { x: X }\n")
      File.write("#{dir}/tsconfig.json", '{"extends": "tsbase/tsconfig.json"}')
      TsSchemaSpec.configure { |c| c.tsconfig = "#{dir}/tsconfig.json" }
      begin
        described_class.generate("#{dir}/a.ts")
      rescue TsSchemaSpec::GenerationError
        nil
      end

      FileUtils.mkdir_p("#{dir}/node_modules/tsbase")
      File.write("#{dir}/node_modules/tsbase/tsconfig.json", '{"compilerOptions": {"paths": {"@x": ["../../x2.ts"]}}}')

      expect(described_class.generate("#{dir}/b.ts").dig("definitions", "X", "properties").keys).to eq(["two"])
    end
  ensure
    TsSchemaSpec.reset_config!
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
