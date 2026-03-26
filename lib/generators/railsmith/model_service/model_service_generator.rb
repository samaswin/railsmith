# frozen_string_literal: true

require "rails/generators"

module Railsmith
  module Generators
    # Scaffolds an `Operations::<Model>Service` class for a given model constant.
    class ModelServiceGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :output_path,
                   type: :string,
                   default: "app/services/operations",
                   desc: "Base path where model services are generated"

      class_option :actions,
                   type: :array,
                   default: [],
                   desc: "Optional action stubs to include (e.g. create update destroy)"

      def create_model_service
        if File.exist?(File.join(destination_root, target_file)) && !options[:force]
          say_status(
            :skip,
            "#{target_file} already exists (use --force to overwrite)",
            :yellow
          )
          return
        end

        template "model_service.rb.tt", target_file
      end

      private

      def target_file
        File.join(options.fetch(:output_path), "#{file_path}_service.rb")
      end

      def service_class_name
        "#{class_name}Service"
      end

      def operations_modules
        ["Operations", *class_name.split("::")[0...-1]]
      end

      def declared_actions
        options
          .fetch(:actions)
          .map { |a| a.to_s.strip }
          .reject(&:empty?)
          .uniq
      end

      def stub_action?(action_name)
        declared_actions.include?(action_name.to_s)
      end
    end
  end
end
