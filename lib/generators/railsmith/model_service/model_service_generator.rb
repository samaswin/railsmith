# frozen_string_literal: true

require "rails/generators"
require "active_support/core_ext/string/inflections"

module Railsmith
  module Generators
    # Scaffolds a service class for a given model constant.
    #
    # Default mode (no flags):
    # - Generates into `app/services/<model>_service.rb` with no module wrapper
    #
    # Namespace mode (--namespace=Billing::Services):
    # - Generates into `app/services/billing/services/<model>_service.rb`
    # - Wraps class in the given modules; auto-adds `service_domain` from first segment
    #
    # Domain mode (--domain=Billing):
    # - Generates into `app/domains/<domain>/services/<model>_service.rb`
    # - Wraps class in `<Domain>::Services::<Model>Service`
    class ModelServiceGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :output_path,
                   type: :string,
                   default: "app/services",
                   desc: "Base path where model services are generated"

      class_option :domains_path,
                   type: :string,
                   default: "app/domains",
                   desc: "Base path where domains live (used with --domain)"

      class_option :namespace,
                   type: :string,
                   default: nil,
                   desc: "Optional module namespace (e.g. Billing::Services)"

      class_option :domain,
                   type: :string,
                   default: nil,
                   desc: "Domain module for domain-mode output (e.g. Billing or Admin::Billing)"

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
        return domain_target_file if domain_mode?
        return namespace_target_file if namespace_given?

        File.join(options[:output_path], "#{file_path}_service.rb")
      end

      def domain_target_file
        File.join(
          options[:domains_path],
          domain_file_path,
          "services",
          "#{model_file_path}_service.rb"
        )
      end

      def namespace_target_file
        simple_name = class_name.split("::").last.underscore
        File.join(options[:output_path], namespace_file_path, "#{simple_name}_service.rb")
      end

      def service_class_name
        "#{class_name}Service"
      end

      def enclosing_modules
        return domain_modules + ["Services"] + model_modules_without_domain if domain_mode?
        return namespace_modules if namespace_given?

        model_modules
      end

      # Indentation for the `class` line — 2 spaces per enclosing module, capped at one level.
      def class_indent
        enclosing_modules.empty? ? "" : "  "
      end

      # Indentation for class body members.
      def member_indent
        enclosing_modules.empty? ? "  " : "    "
      end

      # Returns the first namespace segment underscored (e.g. "billing") to use as
      # service_domain, or nil when no --namespace was given.
      def service_domain_name
        return nil unless namespace_given?

        namespace_modules.first&.underscore
      end

      def namespace_modules
        options[:namespace].to_s.strip.split("::")
      end

      def namespace_given?
        !options[:namespace].to_s.strip.empty?
      end

      def namespace_file_path
        namespace_modules.map(&:underscore).join("/")
      end

      def model_modules
        class_name.split("::")[0...-1]
      end

      def domain_modules
        options[:domain].to_s.strip.split("::")
      end

      def model_modules_without_domain
        class_parts = class_name.split("::")
        remaining = class_parts.drop(domain_modules.length)
        remaining[0...-1]
      end

      def domain_file_path
        domain_modules.map(&:underscore).join("/")
      end

      def model_file_path
        class_parts = class_name.split("::")
        remaining = class_parts.drop(domain_modules.length)
        remaining.map(&:underscore).join("/")
      end

      def domain_mode?
        !options[:domain].to_s.strip.empty?
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
