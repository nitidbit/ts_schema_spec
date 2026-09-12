# frozen_string_literal: true

require "ts_schema_spec/rspec"

RSpec.describe "match_schema" do
  let(:source) { fixture("roleMatrix.ts") }
  let(:valid) { { "id" => 1, "name" => "Nurse", "shortcode" => nil } }

  it "passes a conforming payload" do
    expect(valid).to match_schema(source, "Role")
  end

  it "fails a non-conforming payload" do
    expect(valid.merge("id" => "1")).to_not match_schema(source, "Role")
  end

  it "names the failing pointer in the message" do
    expect {
      expect(valid.merge("id" => "1")).to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, %r{/id:})
  end

  it "says (root) when the payload itself is the wrong shape" do
    expect {
      expect("not a hash").to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /\(root\):/)
  end

  it "dumps the payload" do
    expect {
      expect(valid.merge("id" => "1")).to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Payload was:/)
  end

  it "names an undeclared key" do
    expect {
      expect(valid.merge("created_at" => "2026-09-11")).to match_schema(source, "Role")
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /created_at/)
  end
end
