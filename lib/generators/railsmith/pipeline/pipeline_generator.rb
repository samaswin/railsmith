# frozen_string_literal: true

require "rails/generators"
require "active_support/core_ext/string/inflections"

module Railsmith
  module Generators
    # Scaffolds a Railsmith::Pipeline subclass and its companion spec file.
    #
    # Basic usage:
    # - rails g railsmith:pipeline Checkout
    #   -> app/pipelines/checkout_pipeline.rb
    #   -> spec/pipelines/checkout_pipeline_spec.rb
    #
    # Namespaced (namespace from class name):
    # - rails g railsmith:pipeline Billing::Checkout
    #   -> app/pipelines/billing/checkout_pipeline.rb
    #   -> spec/pipelines/billing/checkout_pipeline_spec.rb
    #   -> module Billing; class CheckoutPipeline
    #
    # Domain mode (--domain):
    # - rails g railsmith:pipeline Checkout --domain=Billing
    #   -> app/domains/billing/pipelines/checkout_pipeline.rb
    #   -> spec/domains/billing/pipelines/checkout_pipeline_spec.rb
    #   -> module Billing; class CheckoutPipeline
    class PipelineGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :output_path,
                   type: :string,
                   default: "app/pipelines",
                   desc: "Base path where pipeline classes are generated"

      class_option :spec_path,
                   type: :string,
                   default: "spec/pipelines",
                   desc: "Base path where pipeline specs are generated"

      class_option :domains_path,
                   type: :string,
                   default: "app/domains",
                   desc: "Base path where domains live (used with --domain)"

      class_option :domain,
                   type: :string,
                   default: nil,
                   desc: "Domain module (e.g. Billing or Admin::Billing)"

      def create_pipeline
        return if skip_existing_file?(target_file)

        template "pipeline.rb.tt", target_file
      end

      def create_spec
        return if skip_existing_file?(spec_file)

        template "pipeline_spec.rb.tt", spec_file
      end

      private

      def skip_existing_file?(relative_path)
        absolute = File.join(destination_root, relative_path)
        return false unless File.exist?(absolute)
        return false if options[:force]

        say_status(:skip, "#{relative_path} already exists (use --force to overwrite)", :yellow)
        true
      end

      # The simple class name for the pipeline, always ending with "Pipeline".
      def pipeline_class_name
        base = class_name.split("::").last
        base.end_with?("Pipeline") ? base : "#{base}Pipeline"
      end

      # Modules wrapping the pipeline class in the generated file.
      def enclosing_modules
        if domain_mode?
          domain_modules + non_domain_intermediate_modules
        else
          class_name.split("::")[0...-1]
        end
      end

      def class_indent
        enclosing_modules.empty? ? "" : "  "
      end

      def member_indent
        enclosing_modules.empty? ? "  " : "    "
      end

      def domain_mode?
        !options[:domain].to_s.strip.empty?
      end

      def domain_modules
        options[:domain].to_s.strip.split("::")
      end

      # Any segments between the domain prefix and the final class name segment.
      def non_domain_intermediate_modules
        parts = class_name.split("::")
        remaining = parts.drop(domain_modules.length)
        remaining[0...-1]
      end

      def target_file
        if domain_mode?
          File.join(options[:domains_path], domain_file_path, "pipelines", "#{pipeline_file_name}.rb")
        else
          File.join(options[:output_path], *namespace_path_segments, "#{pipeline_file_name}.rb")
        end
      end

      def spec_file
        if domain_mode?
          File.join("spec/domains", domain_file_path, "pipelines", "#{pipeline_file_name}_spec.rb")
        else
          File.join(options[:spec_path], *namespace_path_segments, "#{pipeline_file_name}_spec.rb")
        end
      end

      def pipeline_file_name
        base = class_name.split("::").last.underscore
        base.end_with?("_pipeline") ? base : "#{base}_pipeline"
      end

      def domain_file_path
        domain_modules.map(&:underscore).join("/")
      end

      # Directory segments derived from enclosing module names (non-domain mode).
      def namespace_path_segments
        class_name.split("::")[0...-1].map(&:underscore)
      end

      # Fully-qualified class constant for use in the spec file.
      def qualified_pipeline_class_name
        (enclosing_modules + [pipeline_class_name]).join("::")
      end
    end
  end
end
