# frozen_string_literal: true

require "rails/generators"
require "active_support/core_ext/string/inflections"

module Railsmith
  module Generators
    InputSpec = Struct.new(:name, :type_str, :required, keyword_init: true)
    AssocSpec = Struct.new(:macro, :name, :service_class_name, :service_exists, keyword_init: true)

    COLUMN_TYPE_MAP = {
      "string" => "String",
      "text" => "String",
      "integer" => "Integer",
      "bigint" => "Integer",
      "float" => "Float",
      "decimal" => "BigDecimal",
      "boolean" => ":boolean",
      "date" => "Date",
      "datetime" => "DateTime",
      "timestamp" => "DateTime",
      "time" => "Time",
      "json" => "Hash",
      "jsonb" => "Hash",
      "hstore" => "Hash"
    }.freeze

    SYSTEM_COLUMNS = %w[id created_at updated_at].freeze

    # Internal helpers for the model service generator.
    module ModelServiceGeneratorSupport
      private

      def target_file = resolver.target_file
      def enclosing_modules = resolver.enclosing_modules
      def service_domain_name = resolver.service_domain_name
      def service_class_name = "#{class_name}Service"
      def class_indent = enclosing_modules.empty? ? "" : "  "
      def member_indent = enclosing_modules.empty? ? "  " : "    "
      def stub_action?(action_name) = resolver.declared_actions.include?(action_name.to_s)

      def input_declarations
        return [] if options[:inputs].nil?

        options[:inputs].empty? ? introspect_model_inputs : parse_input_specs(options[:inputs])
      end

      def association_declarations
        return [] unless options[:associations]

        introspect_model_associations
      end

      def eager_load_names
        association_declarations.map { |assoc| assoc.name.to_s }
      end

      def resolver
        @resolver ||= Resolver.new(class_name, options)
      end

      def parse_input_specs(specs)
        specs.map do |spec|
          parts = spec.split(":")
          name = parts[0]
          type_key = parts[1]&.downcase || "string"
          type_str = COLUMN_TYPE_MAP.fetch(type_key, "String")
          required = parts[2]&.downcase == "required"
          InputSpec.new(name: name, type_str: type_str, required: required)
        end
      end

      def introspect_model_inputs
        model = try_load_model
        return [] unless model.respond_to?(:columns_hash)

        model.columns_hash
             .except(*SYSTEM_COLUMNS)
             .map do |col_name, column|
               type_str = COLUMN_TYPE_MAP.fetch(column.type.to_s, "String")
               InputSpec.new(name: col_name, type_str: type_str, required: false)
             end
      end

      def introspect_model_associations
        model = try_load_model
        return [] unless model.respond_to?(:reflect_on_all_associations)

        model.reflect_on_all_associations.map { |reflection| assoc_spec_for(reflection) }
      end

      def assoc_spec_for(reflection)
        assoc_name = reflection.name.to_s
        svc_name = "#{assoc_name.classify}Service"
        AssocSpec.new(
          macro: reflection.macro.to_s,
          name: assoc_name,
          service_class_name: svc_name,
          service_exists: Object.const_defined?(svc_name)
        )
      end

      def try_load_model
        Object.const_get(class_name)
      rescue NameError
        say_status(:warning, "Could not load #{class_name} for introspection — skipping", :yellow)
        nil
      end
    end

    # Scaffolds a service class for a given model constant.
    #
    # Default mode (no flags):
    # - Generates into `app/services/<model>_service.rb` with no module wrapper
    #
    # Namespace mode (--namespace=Billing::Services):
    # - Generates into `app/services/billing/services/<model>_service.rb`
    # - Wraps class in the given modules; auto-adds `domain` from first segment
    #
    # Domain mode (--domain=Billing):
    # - Generates into `app/domains/<domain>/services/<model>_service.rb`
    # - Wraps class in `<Domain>::Services::<Model>Service`
    #
    # Input DSL (--inputs or --inputs=name:type[:required] ...):
    # - Without values: introspects model columns (requires model to be loaded)
    # - With values: generates explicit input declarations from the given specs
    #
    # Association DSL (--associations):
    # - Introspects model associations via reflect_on_all_associations
    # - Generates has_many, has_one, belongs_to DSL and includes declaration
    class ModelServiceGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)
      include ModelServiceGeneratorSupport

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

      class_option :inputs,
                   type: :array,
                   default: nil,
                   lazy_default: [],
                   desc: "Input declarations (e.g. email:string:required name:string age:integer). " \
                         "Pass with no values to introspect model columns."

      class_option :associations,
                   type: :boolean,
                   default: false,
                   desc: "Generate association DSL by introspecting the model's associations"

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
    end

    # Computes target file path and enclosing module list for ModelServiceGenerator.
    class Resolver
      def initialize(class_name, options)
        @class_name = class_name
        @options = options
      end

      def target_file
        return domain_target_file if domain_mode?
        return namespace_target_file if namespace_given?

        File.join(@options[:output_path], "#{flat_file_path}_service.rb")
      end

      def enclosing_modules
        return domain_modules + ["Services"] + model_modules_without_domain if domain_mode?
        return namespace_modules if namespace_given?

        model_modules
      end

      def service_domain_name
        return nil unless namespace_given?

        namespace_modules.first&.underscore
      end

      def declared_actions
        @options.fetch(:actions).map { |a| a.to_s.strip }.reject(&:empty?).uniq
      end

      private

      def domain_target_file
        File.join(@options[:domains_path], domain_file_path, "services", "#{model_file_path}_service.rb")
      end

      def namespace_target_file
        simple_name = @class_name.split("::").last.underscore
        File.join(@options[:output_path], namespace_file_path, "#{simple_name}_service.rb")
      end

      def namespace_modules = @options[:namespace].to_s.strip.split("::")
      def namespace_given? = !@options[:namespace].to_s.strip.empty?
      def namespace_file_path = namespace_modules.map(&:underscore).join("/")
      def model_modules = @class_name.split("::")[0...-1]
      def domain_modules = @options[:domain].to_s.strip.split("::")
      def domain_mode? = !@options[:domain].to_s.strip.empty?
      def domain_file_path = domain_modules.map(&:underscore).join("/")
      def flat_file_path = @class_name.split("::").map(&:underscore).join("/")

      def model_modules_without_domain
        class_parts = @class_name.split("::")
        remaining = class_parts.drop(domain_modules.length)
        remaining = class_parts if remaining.empty?
        remaining[0...-1]
      end

      def model_file_path
        class_parts = @class_name.split("::")
        remaining = class_parts.drop(domain_modules.length)
        remaining = class_parts if remaining.empty?
        remaining.map(&:underscore).join("/")
      end
    end
  end
end
