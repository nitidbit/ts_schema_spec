# frozen_string_literal: true

require "ts_schema_spec/rspec"

RSpec.describe "match_schema" do
  let(:source) { fixture("roleMatrix.ts") }
  let(:valid) { { "id" => 1, "name" => "Nurse", "shortcode" => nil } }

  before { allow(RSpec).to receive(:deprecate) }

  it "is deprecated in favor of match_ts_schema" do
    expect(valid).to match_schema(source, "Role")
    expect(RSpec).to have_received(:deprecate).with("match_schema", replacement: "match_ts_schema")
  end

  it "still validates" do
    expect(valid.merge("id" => "1")).to_not match_schema(source, "Role")
  end
end
