# frozen_string_literal: true

require "ts_schema_spec/react_component_props"

RSpec.describe TsSchemaSpec::ReactComponentProps do
  include TsSchemaSpec::ReactComponentProps

  let(:html) { File.read(File.expand_path("../fixtures/rendered.html", __dir__)) }

  it "returns one entry per mount of the component" do
    props = react_component_props("RoleMatrix", html)

    expect(props.length).to eq(2)
    expect(props.map { |p| p["assignedEntity"] }).to eq(%w[account region])
  end

  it "parses the props as JSON" do
    expect(react_component_props("RoleMatrix", html).first).to include("reviewMode" => false)
  end

  it "matches a namespaced react class by its trailing segment" do
    expect(react_component_props("SidebarNav", html).length).to eq(1)
  end

  it "returns an empty array when the component is not mounted" do
    expect(react_component_props("Absent", html)).to eq([])
  end

  it "raises when a mount's props are not parseable" do
    broken = '<div data-react-class="RoleMatrix" data-react-props="{oops"></div>'

    expect { react_component_props("RoleMatrix", broken) }
      .to raise_error(TsSchemaSpec::Error, /RoleMatrix/)
  end
end
