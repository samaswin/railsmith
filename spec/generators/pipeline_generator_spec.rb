# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/pipeline/pipeline_generator"

RSpec.describe Railsmith::Generators::PipelineGenerator do
  def run_generator(args, destination_root)
    described_class.start(args, destination_root: destination_root)
  end

  # ---------------------------------------------------------------------------
  # Basic pipeline + spec generation
  # ---------------------------------------------------------------------------

  it "generates a pipeline class in app/pipelines by default" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)

      expect(File).to exist(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))
    end
  end

  it "generates a companion spec in spec/pipelines by default" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)

      expect(File).to exist(File.join(tmp, "spec/pipelines/checkout_pipeline_spec.rb"))
    end
  end

  it "names the class CheckoutPipeline when given 'Checkout'" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)

      content = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))
      expect(content).to include("class CheckoutPipeline < Railsmith::Pipeline")
    end
  end

  it "does not add a module wrapper for a simple (non-namespaced) name" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)

      content = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))
      expect(content).not_to include("module ")
    end
  end

  it "includes commented-out step examples in the pipeline template" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)

      content = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))
      expect(content).to include("# step :validate")
      expect(content).to include("rollback:")
      expect(content).to include("if:")
    end
  end

  it "inherits from Railsmith::Pipeline" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)

      content = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))
      expect(content).to include("< Railsmith::Pipeline")
    end
  end

  # ---------------------------------------------------------------------------
  # Class name already ending with "Pipeline"
  # ---------------------------------------------------------------------------

  it "does not double-append 'Pipeline' when the name already ends with it" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["CheckoutPipeline"], tmp)

      content = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))
      expect(content).to include("class CheckoutPipeline < Railsmith::Pipeline")
      expect(content).not_to include("class CheckoutPipelinePipeline")
    end
  end

  # ---------------------------------------------------------------------------
  # Namespaced class name (no --domain flag)
  # ---------------------------------------------------------------------------

  it "generates into a subdirectory for a namespaced name" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Billing::Checkout"], tmp)

      expect(File).to exist(File.join(tmp, "app/pipelines/billing/checkout_pipeline.rb"))
      expect(File).to exist(File.join(tmp, "spec/pipelines/billing/checkout_pipeline_spec.rb"))
    end
  end

  it "wraps the class in a module for a namespaced name" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Billing::Checkout"], tmp)

      content = File.read(File.join(tmp, "app/pipelines/billing/checkout_pipeline.rb"))
      expect(content).to include("module Billing")
      expect(content).to include("class CheckoutPipeline < Railsmith::Pipeline")
    end
  end

  # ---------------------------------------------------------------------------
  # Domain mode (--domain)
  # ---------------------------------------------------------------------------

  it "generates into app/domains when --domain is given" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout", "--domain=Billing"], tmp)

      expect(File).to exist(File.join(tmp, "app/domains/billing/pipelines/checkout_pipeline.rb"))
    end
  end

  it "generates the spec into spec/domains when --domain is given" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout", "--domain=Billing"], tmp)

      expect(File).to exist(File.join(tmp, "spec/domains/billing/pipelines/checkout_pipeline_spec.rb"))
    end
  end

  it "wraps the class in the domain module" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout", "--domain=Billing"], tmp)

      content = File.read(File.join(tmp, "app/domains/billing/pipelines/checkout_pipeline.rb"))
      expect(content).to include("module Billing")
      expect(content).to include("class CheckoutPipeline < Railsmith::Pipeline")
    end
  end

  it "supports multi-segment domain names (e.g. Admin::Billing)" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout", "--domain=Admin::Billing"], tmp)

      expect(File).to exist(
        File.join(tmp, "app/domains/admin/billing/pipelines/checkout_pipeline.rb")
      )
      content = File.read(
        File.join(tmp, "app/domains/admin/billing/pipelines/checkout_pipeline.rb")
      )
      expect(content).to include("module Admin")
      expect(content).to include("module Billing")
    end
  end

  # ---------------------------------------------------------------------------
  # Spec file content
  # ---------------------------------------------------------------------------

  it "references the qualified class name in the spec" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Billing::Checkout"], tmp)

      content = File.read(File.join(tmp, "spec/pipelines/billing/checkout_pipeline_spec.rb"))
      expect(content).to include("Billing::CheckoutPipeline")
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency & overwrite guard
  # ---------------------------------------------------------------------------

  it "does not overwrite an existing pipeline file without --force" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)
      pipeline_file = File.join(tmp, "app/pipelines/checkout_pipeline.rb")
      File.write(pipeline_file, "CUSTOM\n")

      run_generator(["Checkout"], tmp)

      expect(File.read(pipeline_file)).to eq("CUSTOM\n")
    end
  end

  it "does not overwrite an existing spec file without --force" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)
      spec_file = File.join(tmp, "spec/pipelines/checkout_pipeline_spec.rb")
      File.write(spec_file, "CUSTOM SPEC\n")

      run_generator(["Checkout"], tmp)

      expect(File.read(spec_file)).to eq("CUSTOM SPEC\n")
    end
  end

  it "is idempotent when run twice with the same arguments" do
    Dir.mktmpdir("railsmith-pipeline-generator-spec") do |tmp|
      run_generator(["Checkout"], tmp)
      first = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))

      run_generator(["Checkout"], tmp)
      second = File.read(File.join(tmp, "app/pipelines/checkout_pipeline.rb"))

      expect(second).to eq(first)
    end
  end
end
