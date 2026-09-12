# frozen_string_literal: true

require "ts_schema_spec/rspec"

RSpec.describe "match_schema with a collection" do
  let(:source) { fixture("roleMatrix.ts") }
  let(:role) { { "id" => 1, "name" => "Nurse", "shortcode" => nil } }

  it "passes when every item matches" do
    expect([role, role.merge("id" => 2)]).to match_schema(source, "Role")
  end

  it "fails when any item does not match" do
    expect([role, role.merge("id" => "2")]).to_not match_schema(source, "Role")
  end

  it "names which item failed" do
    expect {
      expect([role, role.merge("id" => "2")]).to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, %r{/1/id})
  end

  it "fails on an empty collection rather than passing vacuously" do
    expect {
      expect([]).to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /empty/)
  end

  it "explains what an empty collection usually means" do
    expect {
      expect([]).to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /rendered|no records/)
  end

  it "still validates an array-typed schema against the array itself" do
    expect([role]).to match_schema(source, "RoleList")
  end

  it "accepts an empty array when the schema itself describes an array" do
    expect([]).to match_schema(source, "RoleList")
  end

  it "still handles a single object" do
    expect(role).to match_schema(source, "Role")
  end
end
