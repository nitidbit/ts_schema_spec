# frozen_string_literal: true

require "ts_schema_spec/rspec"

RSpec.describe "match_schema(path, type)" do
  let(:role) { { "id" => 1, "name" => "Nurse", "shortcode" => nil } }

  it "takes the source and type directly" do
    expect(role).to match_schema(fixture("roleMatrix.ts"), "Role")
  end

  it "fails a non-conforming payload" do
    expect(role.merge("id" => "1")).to_not match_schema(fixture("roleMatrix.ts"), "Role")
  end

  it "names the type and the source in the failure message" do
    expect {
      expect(role.merge("id" => "1")).to match_schema(fixture("roleMatrix.ts"), "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Role.*roleMatrix\.ts/m)
  end

  it "still raises for a type that is not exported" do
    expect {
      expect(role).to match_schema(fixture("roleMatrix.ts"), "NotExported")
    }.to raise_error(TsSchemaSpec::GenerationError, /exported\?/)
  end

  it "says so when the arguments are reversed" do
    expect {
      expect(role).to match_schema("Role", fixture("roleMatrix.ts"))
    }.to raise_error(ArgumentError, /reversed/i)
  end

  it "says so when the type is missing" do
    expect {
      expect(role).to match_schema(fixture("roleMatrix.ts"))
    }.to raise_error(ArgumentError, /path.*type/i)
  end
end
