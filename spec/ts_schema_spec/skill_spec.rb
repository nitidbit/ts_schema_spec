# frozen_string_literal: true

require "tmpdir"
require "ts_schema_spec/skill"

RSpec.describe TsSchemaSpec::Skill do
  around { |example| Dir.mktmpdir { |dir| @root = dir; example.run } }

  attr_reader :root

  def installed
    File.read(File.join(root, TsSchemaSpec::Skill::INSTALL_PATH))
  end

  it "installs the skill into the consumer's .claude/skills" do
    described_class.install(root)

    expect(installed).to include("name: react-prop-type-spec")
  end

  it "stamps the gem version into the installed copy" do
    described_class.install(root)

    expect(described_class.installed_version(root)).to eq(TsSchemaSpec::VERSION)
  end

  it "re-stamps rather than accumulating stamps on reinstall" do
    described_class.install(root)
    described_class.install(root)

    expect(installed.scan(/ts_schema_spec_version:/).length).to eq(1)
  end

  it "passes the staleness check once installed" do
    described_class.install(root)

    expect { described_class.check!(root) }.to_not raise_error
  end

  it "fails the staleness check when the stamp is behind the gem" do
    described_class.install(root)
    path = File.join(root, TsSchemaSpec::Skill::INSTALL_PATH)
    File.write(path, installed.sub(TsSchemaSpec::VERSION, "0.0.1"))

    expect { described_class.check!(root) }
      .to raise_error(TsSchemaSpec::Error, /rake ts_schema_spec:install_skill/)
  end

  it "fails the staleness check when the skill was never installed" do
    expect { described_class.check!(root) }
      .to raise_error(TsSchemaSpec::Error, /rake ts_schema_spec:install_skill/)
  end
end
