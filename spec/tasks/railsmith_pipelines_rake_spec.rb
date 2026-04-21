# frozen_string_literal: true

require "spec_helper"
require "railsmith"
require "railsmith/pipeline"
require "rake"

RSpec.describe "railsmith:pipelines rake task" do
  let(:task_path) { File.expand_path("../../lib/tasks/railsmith.rake", __dir__) }

  # Define a fresh Rake application for each example to avoid task re-definition
  # warnings and cross-test leakage.
  before do
    Rake.application = Rake::Application.new
    # Stub :environment so the task dependency resolves without a full Rails app.
    Rake::Task.define_task(:environment)
    load task_path
  end

  def invoke_task
    Rake.application["railsmith:pipelines"].invoke
  end

  context "when no pipelines are loaded" do
    it "prints a 'no pipelines found' message" do
      expect { invoke_task }.to output(/No Railsmith pipelines found/i).to_stdout
    end
  end

  context "when a pipeline subclass is defined" do
    let!(:pipeline_class) do
      stub_const("TestSpecPipeline", Class.new(Railsmith::Pipeline))
    end

    it "prints the pipeline class name" do
      expect { invoke_task }.to output(/TestSpecPipeline/).to_stdout
    end

    it "notes when there are no steps" do
      expect { invoke_task }.to output(/no steps declared/).to_stdout
    end
  end

  context "when a pipeline has steps" do
    let!(:step_service) { stub_const("FakeStepService", Class.new) }

    let!(:pipeline_class) do
      svc = step_service
      stub_const("SteppedSpecPipeline", Class.new(Railsmith::Pipeline) do
        step :do_thing, service: svc, action: :perform
      end)
    end

    it "prints each step name" do
      expect { invoke_task }.to output(/step :do_thing/).to_stdout
    end

    it "prints the service name" do
      expect { invoke_task }.to output(/FakeStepService/).to_stdout
    end

    it "prints the action" do
      expect { invoke_task }.to output(/action: :perform/).to_stdout
    end
  end

  context "when a step has a rollback symbol" do
    let!(:step_service) { stub_const("RollbackService", Class.new) }

    let!(:pipeline_class) do
      svc = step_service
      stub_const("RollbackSpecPipeline", Class.new(Railsmith::Pipeline) do
        step :reserve, service: svc, action: :reserve, rollback: :unreserve
      end)
    end

    it "prints the rollback symbol" do
      expect { invoke_task }.to output(/rollback: :unreserve/).to_stdout
    end
  end

  context "when a step has a conditional" do
    let!(:step_service) { stub_const("ConditionalService", Class.new) }

    let!(:pipeline_class) do
      svc = step_service
      stub_const("ConditionalSpecPipeline", Class.new(Railsmith::Pipeline) do
        step :maybe, service: svc, action: :run, if: ->(_p, _c) { true }
      end)
    end

    it "indicates the if: condition" do
      expect { invoke_task }.to output(/if: \.\.\./).to_stdout
    end
  end
end
