# frozen_string_literal: true

require "spec_helper"
require "railsmith/arch_checks"
require "fileutils"

RSpec.describe Railsmith::ArchChecks::Cli do
  let(:fixtures_controllers) { File.expand_path("../../fixtures/controllers", __dir__) }

  after do
    ENV.delete_if { |key, _| key.start_with?("RAILSMITH_") }
    Railsmith.configuration = Railsmith::Configuration.new
  end

  describe ".run" do
    it "prints a text report and returns 0 when fail-on is off (default)" do
      env = {
        "RAILSMITH_PATHS" => fixtures_controllers,
        "RAILSMITH_FORMAT" => "text"
      }
      out = StringIO.new
      warnings = []
      warn_proc = proc { |message| warnings << message }

      status = described_class.run(env: env, output: out, warn_proc: warn_proc)

      expect(status).to eq(0)
      expect(out.string).to match(/violations found/)
      expect(warnings).to be_empty
    end

    it "returns 1 when RAILSMITH_FAIL_ON_ARCH_VIOLATIONS is true and violations exist" do
      env = {
        "RAILSMITH_PATHS" => fixtures_controllers,
        "RAILSMITH_FAIL_ON_ARCH_VIOLATIONS" => "true",
        "RAILSMITH_FORMAT" => "json"
      }
      out = StringIO.new

      status = described_class.run(env: env, output: out)

      expect(status).to eq(1)
      expect(out.string).not_to be_empty
      expect(JSON.parse(out.string).dig("summary", "fail_on_arch_violations")).to be true
    end

    it "prints fail-on footer in text mode when fail-on is enabled" do
      env = {
        "RAILSMITH_PATHS" => fixtures_controllers,
        "RAILSMITH_FAIL_ON_ARCH_VIOLATIONS" => "true",
        "RAILSMITH_FORMAT" => "text"
      }
      out = StringIO.new

      described_class.run(env: env, output: out)

      expect(out.string).to include("fail-on mode is enabled")
    end

    it "prints warn-only footer in text mode when fail-on is off" do
      env = {
        "RAILSMITH_PATHS" => fixtures_controllers,
        "RAILSMITH_FORMAT" => "text"
      }
      out = StringIO.new

      described_class.run(env: env, output: out)

      expect(out.string).to include("warn-only mode")
    end

    it "returns 1 when configuration.fail_on_arch_violations is true" do
      ENV.delete("RAILSMITH_FAIL_ON_ARCH_VIOLATIONS")
      Railsmith.configuration.fail_on_arch_violations = true
      env = { "RAILSMITH_PATHS" => fixtures_controllers }
      out = StringIO.new

      status = described_class.run(env: env, output: out)

      expect(status).to eq(1)
    end

    it "returns 0 when fail-on is requested but the scan is clean" do
      env = {
        "RAILSMITH_FAIL_ON_ARCH_VIOLATIONS" => "true",
        "RAILSMITH_FORMAT" => "text"
      }
      out = StringIO.new

      Dir.mktmpdir do |dir|
        FileUtils.cp(
          File.join(fixtures_controllers, "clean_controller.rb"),
          File.join(dir, "clean_controller.rb")
        )
        env["RAILSMITH_PATHS"] = dir

        status = described_class.run(env: env, output: out)

        expect(status).to eq(0)
      end
    end

    it "returns 0 when env explicitly disables fail-on even if config is enabled" do
      env = {
        "RAILSMITH_FAIL_ON_ARCH_VIOLATIONS" => "false",
        "RAILSMITH_PATHS" => fixtures_controllers
      }
      out = StringIO.new
      Railsmith.configuration.fail_on_arch_violations = true

      status = described_class.run(env: env, output: out)

      expect(status).to eq(0)
    end

    it "records a warning and falls back to text when RAILSMITH_FORMAT is invalid" do
      warnings = []
      warn_proc = proc { |message| warnings << message }

      Dir.mktmpdir do |dir|
        FileUtils.cp(
          File.join(fixtures_controllers, "clean_controller.rb"),
          File.join(dir, "clean_controller.rb")
        )
        env = {
          "RAILSMITH_PATHS" => dir,
          "RAILSMITH_FORMAT" => "yaml"
        }
        out = StringIO.new

        status = described_class.run(env: env, output: out, warn_proc: warn_proc)

        expect(status).to eq(0)
        expect(warnings.join).to match(/invalid RAILSMITH_FORMAT/)
        expect(out.string).to match(/OK — no violations found/)
      end
    end
  end
end
