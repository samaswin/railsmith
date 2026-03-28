# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith.deep_dup" do
  it "deep-copies nested hashes" do
    original = { a: { b: 1 } }
    copy = Railsmith.deep_dup(original)
    copy[:a][:b] = 2
    expect(original[:a][:b]).to eq(1)
  end

  it "returns non-dupable scalars unchanged" do
    expect(Railsmith.deep_dup(:sym)).to eq(:sym)
  end
end
