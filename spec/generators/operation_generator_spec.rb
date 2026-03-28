# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/operation/operation_generator"

RSpec.describe Railsmith::Generators::OperationGenerator do
  def run_generator(args, destination_root)
    described_class.start(args, destination_root: destination_root)
  end

  it "generates an operation for a simple domain" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)

      expect(File).to exist(
        File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")
      )
    end
  end

  it "generates an operation for a namespaced domain with --domain" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Admin::Billing::Invoices::Create", "--domain=Admin::Billing"], temp_dir)

      expect(File).to exist(
        File.join(temp_dir, "app/domains/admin/billing/operations/invoices/create.rb")
      )
    end
  end

  it "is idempotent when run twice" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)
      initial_content = File.read(
        File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")
      )

      run_generator(["Billing::Invoices::Create"], temp_dir)
      second_content = File.read(
        File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")
      )

      expect(second_content).to eq(initial_content)
    end
  end

  it "does not overwrite an existing file without --force" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)
      file = File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")
      File.write(file, "CUSTOM\n")

      run_generator(["Billing::Invoices::Create"], temp_dir)

      expect(File.read(file)).to eq("CUSTOM\n")
    end
  end

  it "generates a callable class that returns a Result" do
    Dir.mktmpdir("railsmith-operation-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoices::Create"], temp_dir)

      load File.join(temp_dir, "app/domains/billing/operations/invoices/create.rb")

      result = Billing::Operations::Invoices::Create.call(
        params: { invoice_id: 1 },
        context: { current_domain: :billing }
      )

      expect(result).to be_a(Railsmith::Result)
      expect(result).to be_success
      expect(result.value).to eq({ current_domain: :billing })
    ensure
      Object.send(:remove_const, :Billing) if Object.const_defined?(:Billing)
    end
  end
end
