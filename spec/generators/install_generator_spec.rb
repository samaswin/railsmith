# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/install/install_generator"

RSpec.describe Railsmith::Generators::InstallGenerator do
  def run_generator(destination_root)
    described_class.start([], destination_root: destination_root)
  end

  it "creates initializer and service folders" do
    Dir.mktmpdir("railsmith-generator-spec") do |temp_dir|
      run_generator(temp_dir)

      expect(File).to exist(File.join(temp_dir, "config/initializers/railsmith.rb"))
      expect(File).to exist(File.join(temp_dir, "app/services"))
    end
  end

  it "is idempotent when run twice" do
    Dir.mktmpdir("railsmith-generator-spec") do |temp_dir|
      run_generator(temp_dir)
      initial_content = File.read(File.join(temp_dir, "config/initializers/railsmith.rb"))

      run_generator(temp_dir)
      second_content = File.read(File.join(temp_dir, "config/initializers/railsmith.rb"))

      expect(second_content).to eq(initial_content)
    end
  end
end
