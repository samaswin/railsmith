# frozen_string_literal: true

require "rails/generators"

module Railsmith
  module Generators
    # Scaffolds a domain module skeleton under `app/domains`.
    class DomainGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :output_path,
                   type: :string,
                   default: "app/domains",
                   desc: "Base path where domains are generated"

      def create_domain_module
        return if skip_existing_file?(target_file)

        create_domain_directories
        template "domain.rb.tt", target_file
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

      def create_domain_directories
        empty_directory domain_directory
        empty_directory File.join(domain_directory, "operations")
        empty_directory File.join(domain_directory, "services")
      end

      def target_file
        File.join(options.fetch(:output_path), "#{file_path}.rb")
      end

      def domain_directory
        File.join(options.fetch(:output_path), file_path)
      end

      def domain_modules
        class_name.split("::")
      end
    end
  end
end
