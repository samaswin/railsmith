# frozen_string_literal: true

require "rails/generators"
require "active_support/core_ext/string/inflections"

module Railsmith
  module Generators
    # Scaffolds a domain operation class that returns `Railsmith::Result`.
    #
    # Default mode (no --namespace):
    # - rails g railsmith:operation Billing::Invoices::Create
    #   -> app/domains/billing/invoices/create.rb
    #   -> module Billing; module Invoices; class Create
    #
    # With --namespace (backward compat / explicit interstitial):
    # - rails g railsmith:operation Billing::Invoices::Create --namespace=Operations
    #   -> app/domains/billing/operations/invoices/create.rb
    #   -> module Billing; module Operations; module Invoices; class Create
    #
    # Namespaced domain (--domain):
    # - rails g railsmith:operation Admin::Billing::Invoices::Create --domain=Admin::Billing
    #   -> app/domains/admin/billing/invoices/create.rb
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

      class_option :namespace,
                   type: :string,
                   default: nil,
                   desc: "Optional interstitial namespace inserted between domain and operation (e.g. Operations)"

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

      def namespace_modules
        ns = options[:namespace].to_s.strip
        ns.empty? ? [] : ns.split("::")
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
        File.join(domain_file_path, *namespace_file_segments, *operation_file_segments, "#{file_name}.rb")
      end

      def domain_file_path
        domain_modules.map(&:underscore).join("/")
      end

      def namespace_file_segments
        namespace_modules.map(&:underscore)
      end

      def operation_file_segments
        operation_modules.map(&:underscore)
      end

      def declared_modules
        domain_modules + namespace_modules + operation_modules
      end

      # Indentation for the `class` line — 2 spaces when there are enclosing modules.
      def class_indent
        declared_modules.empty? ? "" : "  "
      end

      # Indentation for class body members.
      def member_indent
        declared_modules.empty? ? "  " : "    "
      end
    end
  end
end
