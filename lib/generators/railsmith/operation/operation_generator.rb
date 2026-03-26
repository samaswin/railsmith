# frozen_string_literal: true

require "rails/generators"
require "active_support/core_ext/string/inflections"

module Railsmith
  module Generators
    # Scaffolds a domain operation class that returns `Railsmith::Result`.
    #
    # Example:
    # - rails g railsmith:operation Billing::Invoices::Create
    #   -> Billing::Operations::Invoices::Create
    #
    # Namespaced domain:
    # - rails g railsmith:operation Admin::Billing::Invoices::Create --domain=Admin::Billing
    class OperationGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :domains_path,
                   type: :string,
                   default: "app/domains",
                   desc: "Base path where domains live"

      class_option :domain,
                   type: :string,
                   default: nil,
                   desc: "Domain module for namespaced domains (e.g. Admin::Billing)"

      def create_operation
        relative_target = File.join(options.fetch(:domains_path), target_file)
        return if skip_existing_file?(relative_target)

        empty_directory File.dirname(File.join(destination_root, relative_target))
        template "operation.rb.tt", relative_target
      end

      private

      def skip_existing_file?(relative_path)
        absolute = File.join(destination_root, relative_path)
        return false unless File.exist?(absolute)
        return false if options[:force]

        say_status(
          :skip,
          "#{relative_path} already exists (use --force to overwrite)",
          :yellow
        )
        true
      end

      def domain_modules
        explicit = options[:domain].to_s.strip
        return explicit.split("::") unless explicit.empty?

        [class_name.split("::").first]
      end

      def operation_modules
        parts = class_name.split("::")
        return [] if parts.length < 2

        remaining = parts.drop(domain_modules.length)
        remaining[0...-1]
      end

      def operation_class_name
        class_name.split("::").last
      end

      def target_file
        File.join(domain_file_path, "operations", *operation_file_segments, "#{file_name}.rb")
      end

      def domain_file_path
        domain_modules.map(&:underscore).join("/")
      end

      def operation_file_segments
        operation_modules.map(&:underscore)
      end

      def declared_modules
        domain_modules + ["Operations"] + operation_modules
      end
    end
  end
end
