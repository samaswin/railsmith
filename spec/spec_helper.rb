# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/lib/generators/"
  add_group "Input DSL",       %w[lib/railsmith/base_service/input_dsl.rb
                                  lib/railsmith/base_service/input_definition.rb
                                  lib/railsmith/base_service/input_registry.rb]
  add_group "Type Coercion",   "lib/railsmith/base_service/type_coercion.rb"
  add_group "Input Resolver",  "lib/railsmith/base_service/input_resolver.rb"
  add_group "Association DSL", %w[lib/railsmith/base_service/association_dsl.rb
                                  lib/railsmith/base_service/association_definition.rb
                                  lib/railsmith/base_service/association_registry.rb]
  add_group "Eager Loading",   "lib/railsmith/base_service/eager_loading.rb"
  add_group "Nested Writer",   "lib/railsmith/base_service/nested_writer.rb"
  add_group "Bulk",            %w[lib/railsmith/base_service/bulk_actions.rb
                                  lib/railsmith/base_service/bulk_execution.rb
                                  lib/railsmith/base_service/bulk_contract.rb
                                  lib/railsmith/base_service/bulk_params.rb]
  add_group "call! / Failure", %w[lib/railsmith/failure.rb lib/railsmith/controller_helpers.rb]
  add_group "Core",            %w[lib/railsmith/base_service.rb lib/railsmith/result.rb lib/railsmith/errors.rb]
end

require "active_support/concern"
require "railsmith"
require "timecop"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
