# frozen_string_literal: true

RSpec.describe Railsmith do
  it "has a version number" do
    expect(Railsmith::VERSION).not_to be nil
  end

  describe ".configuration" do
    it "provides baseline config defaults" do
      config = described_class.configuration

      expect(config.warn_on_cross_domain_calls).to be(true)
      expect(config.strict_mode).to be(false)
      expect(config.fail_on_arch_violations).to be(false)
      expect(config.serializer_adapter).to eq(:auto)
      expect(config.cross_domain_allowlist).to eq([])
      expect(config.on_cross_domain_violation).to be_nil
    end
  end

  describe ".configure" do
    after do
      described_class.configuration = Railsmith::Configuration.new
    end

    it "yields mutable configuration" do
      described_class.configure do |config|
        config.strict_mode = true
      end

      expect(described_class.configuration.strict_mode).to be(true)
    end
  end
end
