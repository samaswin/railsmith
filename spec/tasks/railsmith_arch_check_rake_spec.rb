# frozen_string_literal: true

require "spec_helper"
require "rake"
require "fileutils"

RSpec.describe "railsmith:arch_check rake task" do
  let(:task_path) { File.expand_path("../../lib/tasks/railsmith.rake", __dir__) }
  let(:fixtures_controllers) { File.expand_path("../fixtures/controllers", __dir__) }

  def load_task_into_fresh_app!
    Rake.application = Rake::Application.new
    load task_path
  end

  def clear_railsmith_env!
    ENV.delete_if { |key, _| key.start_with?("RAILSMITH_") }
  end

  before do
    load_task_into_fresh_app!
  end

  after do
    clear_railsmith_env!
    Railsmith.configuration = Railsmith::Configuration.new
  end

  it "prints a report and does not call exit when fail-on is off (default)" do
    ENV["RAILSMITH_PATHS"] = fixtures_controllers
    ENV["RAILSMITH_FORMAT"] = "text"

    expect(Kernel).not_to receive(:exit)

    expect { Rake.application["railsmith:arch_check"].invoke }.to output(/violations found/).to_stdout
  end

  it "exits 1 when RAILSMITH_FAIL_ON_ARCH_VIOLATIONS is true and violations exist" do
    ENV["RAILSMITH_PATHS"] = fixtures_controllers
    ENV["RAILSMITH_FAIL_ON_ARCH_VIOLATIONS"] = "true"
    ENV["RAILSMITH_FORMAT"] = "json"

    expect(Kernel).to receive(:exit).with(1)

    expect { Rake.application["railsmith:arch_check"].invoke }.to output.to_stdout
  end

  it "exits 1 when configuration.fail_on_arch_violations is true" do
    ENV.delete("RAILSMITH_FAIL_ON_ARCH_VIOLATIONS")
    Railsmith.configuration.fail_on_arch_violations = true
    ENV["RAILSMITH_PATHS"] = fixtures_controllers

    expect(Kernel).to receive(:exit).with(1)

    expect { Rake.application["railsmith:arch_check"].invoke }.to output.to_stdout
  end

  it "does not exit when fail-on is requested but the scan is clean" do
    ENV["RAILSMITH_FAIL_ON_ARCH_VIOLATIONS"] = "true"
    Railsmith.configuration.fail_on_arch_violations = true

    Dir.mktmpdir do |dir|
      FileUtils.cp(
        File.join(fixtures_controllers, "clean_controller.rb"),
        File.join(dir, "clean_controller.rb")
      )
      ENV["RAILSMITH_PATHS"] = dir

      expect(Kernel).not_to receive(:exit)

      expect { Rake.application["railsmith:arch_check"].invoke }.to output.to_stdout
    end
  end

  it "does not exit when env explicitly disables fail-on even if config is enabled" do
    ENV["RAILSMITH_FAIL_ON_ARCH_VIOLATIONS"] = "false"
    Railsmith.configuration.fail_on_arch_violations = true
    ENV["RAILSMITH_PATHS"] = fixtures_controllers

    expect(Kernel).not_to receive(:exit)

    expect { Rake.application["railsmith:arch_check"].invoke }.to output.to_stdout
  end

  it "warns on stderr and falls back to text when RAILSMITH_FORMAT is invalid" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(
        File.join(fixtures_controllers, "clean_controller.rb"),
        File.join(dir, "clean_controller.rb")
      )
      ENV["RAILSMITH_PATHS"] = dir
      ENV["RAILSMITH_FORMAT"] = "yaml"

      expect { Rake.application["railsmith:arch_check"].invoke }
        .to output(/invalid RAILSMITH_FORMAT/).to_stderr
        .and output(/OK — no violations found/).to_stdout
    end
  end
end
