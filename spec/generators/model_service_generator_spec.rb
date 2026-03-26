# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/model_service/model_service_generator"

RSpec.describe Railsmith::Generators::ModelServiceGenerator do
  def run_generator(args, destination_root)
    described_class.start(args, destination_root: destination_root)
  end

  it "generates a service for a single model" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/services/operations/user_service.rb"))
    end
  end

  it "generates a service for a namespaced model" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["Admin::User"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/services/operations/admin/user_service.rb"))
    end
  end

  it "is idempotent when run twice" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)
      initial_content = File.read(File.join(temp_dir, "app/services/operations/user_service.rb"))

      run_generator(["User"], temp_dir)
      second_content = File.read(File.join(temp_dir, "app/services/operations/user_service.rb"))

      expect(second_content).to eq(initial_content)
    end
  end

  it "supports a custom output path" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User", "--output-path=app/services/custom_ops"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/services/custom_ops/user_service.rb"))
    end
  end

  it "generates a callable class" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      class ::User
        def self.transaction
          yield
        end

        def self.find_by(*)
          nil
        end

        attr_reader :errors

        def initialize(attributes = {})
          @attributes = attributes
          @persisted = false
          @destroyed = false
          @errors = []
        end

        def assign_attributes(attributes)
          @attributes.merge!(attributes)
        end

        def save
          @persisted = true
        end

        def destroy
          @destroyed = true
        end

        def persisted?
          @persisted
        end

        def destroyed?
          @destroyed
        end
      end

      load File.join(temp_dir, "app/services/operations/user_service.rb")

      result = Operations::UserService.call(action: :create, params: { attributes: { name: "A" } })
      expect(result).to be_a(Railsmith::Result)
      expect(result).to be_success
    ensure
      Object.send(:remove_const, :User) if Object.const_defined?(:User)
      Object.send(:remove_const, :Operations) if Object.const_defined?(:Operations)
    end
  end
end
