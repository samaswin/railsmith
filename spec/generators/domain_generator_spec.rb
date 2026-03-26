# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/domain/domain_generator"

RSpec.describe Railsmith::Generators::DomainGenerator do
  def run_generator(args, destination_root)
    described_class.start(args, destination_root: destination_root)
  end

  it "generates a simple domain module and directories" do
    Dir.mktmpdir("railsmith-domain-generator-spec") do |temp_dir|
      run_generator(["Billing"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/domains/billing.rb"))
      expect(File).to exist(File.join(temp_dir, "app/domains/billing/operations"))
      expect(File).to exist(File.join(temp_dir, "app/domains/billing/services"))
    end
  end

  it "generates a namespaced domain module and directories" do
    Dir.mktmpdir("railsmith-domain-generator-spec") do |temp_dir|
      run_generator(["Admin::Billing"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/domains/admin/billing.rb"))
      expect(File).to exist(File.join(temp_dir, "app/domains/admin/billing/operations"))
      expect(File).to exist(File.join(temp_dir, "app/domains/admin/billing/services"))
    end
  end

  it "is idempotent when run twice" do
    Dir.mktmpdir("railsmith-domain-generator-spec") do |temp_dir|
      run_generator(["Billing"], temp_dir)
      initial_content = File.read(File.join(temp_dir, "app/domains/billing.rb"))

      run_generator(["Billing"], temp_dir)
      second_content = File.read(File.join(temp_dir, "app/domains/billing.rb"))

      expect(second_content).to eq(initial_content)
    end
  end
end
