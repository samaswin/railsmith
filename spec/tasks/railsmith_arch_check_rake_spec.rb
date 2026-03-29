# frozen_string_literal: true

require "spec_helper"
require "railsmith/arch_checks"
require "rake"

RSpec.describe "railsmith:arch_check rake task" do
  let(:task_path) { File.expand_path("../../lib/tasks/railsmith.rake", __dir__) }

  before do
    Rake.application = Rake::Application.new
    load task_path
  end

  it "delegates to Railsmith::ArchChecks::Cli.run and does not exit on success" do
    expect(Railsmith::ArchChecks::Cli).to receive(:run).and_return(0)
    expect(Kernel).not_to receive(:exit)

    Rake.application["railsmith:arch_check"].invoke
  end
end
