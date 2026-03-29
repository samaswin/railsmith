# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/operation/operation_generator"

RSpec.describe Railsmith::Generators::OperationGenerator do
  def run_generator(args, destination_root)
    described_class.start(args, destination_root: destination_root)
  end

  it "generates an operation without an interstitial namespace by default" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)

      expect(File).to exist(
        File.join(temp_dir, "app/domains/billing/invoices/create.rb")
      )
    end
  end

  it "does not emit an Operations module by default" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)

      content = File.read(File.join(temp_dir, "app/domains/billing/invoices/create.rb"))
      expect(content).not_to include("module Operations")
      expect(content).to include("module Billing")
      expect(content).to include("module Invoices")
      expect(content).to include("class Create")
    end
  end

  it "supports --namespace to insert an interstitial module (e.g. Operations for backward compat)" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create", "--namespace=Operations"], temp_dir)

      expect(File).to exist(
        File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")
      )
      content = File.read(
        File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")
      )
      expect(content).to include("module Operations")
      expect(content).to include("Billing::Operations::Invoices::Create")
    end
  end

  it "generates an operation for a namespaced domain with --domain" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Admin::Billing::Invoices::Create", "--domain=Admin::Billing"], temp_dir)

      expect(File).to exist(
        File.join(temp_dir, "app/domains/admin/billing/invoices/create.rb")
      )
    end
  end

  it "is idempotent when run twice" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)
      initial_content = File.read(
        File.join(temp_dir, "app/domains/billing/invoices/create.rb")
      )

      run_generator(["Billing::Invoices::Create"], temp_dir)
      second_content = File.read(
        File.join(temp_dir, "app/domains/billing/invoices/create.rb")
      )

      expect(second_content).to eq(initial_content)
    end
  end

  it "does not overwrite an existing file without --force" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)
      file = File.join(temp_dir, "app/domains/billing/invoices/create.rb")
      File.write(file, "CUSTOM\n")

      run_generator(["Billing::Invoices::Create"], temp_dir)

      expect(File.read(file)).to eq("CUSTOM\n")
    end
  end

  it "generates a callable class that returns a Result" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)

      load File.join(temp_dir, "app/domains/billing/invoices/create.rb")

      result = Billing::Invoices::Create.call(
        params: { invoice_id: 1 },
        context: { current_domain: "billing" }
      )

      expect(result).to be_a(Railsmith::Result)
      expect(result).to be_success
      expect(result.value).to eq({ current_domain: :billing })
    ensure
      Object.send(:remove_const, :Billing) if Object.const_defined?(:Billing)
    end
  end

  it "does not mutate the caller context hash" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)

      load File.join(temp_dir, "app/domains/billing/invoices/create.rb")

      ctx = { current_domain: :billing, note: "keep" }
      Billing::Invoices::Create.call(params: {}, context: ctx)

      expect(ctx[:current_domain]).to eq(:billing)
      expect(ctx[:note]).to eq("keep")
    ensure
      Object.send(:remove_const, :Billing) if Object.const_defined?(:Billing)
    end
  end
end
