# frozen_string_literal: true

module Railsmith
  module ArchChecks
    # Extracts public instance methods from a controller source line list using indentation.
    module ControllerActionMethodExtractor
      class << self
        # @param lines [Array<String>]
        # @return [Array<Hash>] each hash has :name, :start (line), :indent, :body (String lines)
        def extract(lines)
          methods = []
          state = initial_state

          lines.each_with_index do |raw, idx|
            process_line(raw, idx + 1, state, methods)
          end

          methods
        end

        private

        def initial_state
          {
            current: nil,
            method_indent: nil,
            class_method_indent: nil,
            private_section: false
          }
        end

        def process_line(raw, lineno, state, methods)
          indent = raw.length - raw.lstrip.length
          stripped = raw.strip

          return if stripped.empty? || stripped.start_with?("#")

          detect_class_method_indent(stripped, indent, state)
          return if visibility_keyword_consumed?(stripped, indent, state)

          handle_def_or_body(stripped, indent, lineno, state, methods)
        end

        def detect_class_method_indent(stripped, indent, state)
          return unless state[:current].nil? && state[:class_method_indent].nil?
          return unless def_or_visibility_start?(stripped)

          state[:class_method_indent] = indent
        end

        def def_or_visibility_start?(stripped)
          stripped.match?(/\Adef\s+[a-z_]/) || visibility_keyword_line?(stripped)
        end

        # @return [Boolean] true if this line was a bare visibility keyword (no further processing)
        def visibility_keyword_consumed?(stripped, indent, state)
          return false unless at_class_visibility_indent?(state, indent)

          consume_visibility_keyword?(stripped, state)
        end

        def at_class_visibility_indent?(state, indent)
          state[:current].nil? && state[:class_method_indent] && indent == state[:class_method_indent]
        end

        def consume_visibility_keyword?(stripped, state)
          if visibility_private_line?(stripped)
            state[:private_section] = true
            true
          elsif visibility_public_line?(stripped)
            state[:private_section] = false
            true
          else
            false
          end
        end

        def handle_def_or_body(stripped, indent, lineno, state, methods)
          if state[:current].nil? && (m = stripped.match(/\Adef\s+([a-z_]\w*)/))
            start_method(m, indent, lineno, state) unless state[:private_section]
          elsif state[:current]
            continue_or_close_method(stripped, indent, lineno, state, methods)
          end
        end

        def start_method(match, indent, lineno, state)
          state[:current] = { name: match[1], start: lineno, indent: indent, body: [] }
          state[:method_indent] = indent
        end

        def continue_or_close_method(stripped, indent, lineno, state, methods)
          if method_close_line?(stripped) && indent == state[:method_indent]
            state[:current][:end] = lineno
            methods << state[:current]
            state[:current] = nil
            state[:method_indent] = nil
          else
            state[:current][:body] << stripped
          end
        end

        def method_close_line?(stripped)
          stripped.match?(/\Aend(?:\s*#.*)?$/)
        end

        def visibility_keyword_line?(stripped)
          visibility_private_line?(stripped) || visibility_public_line?(stripped)
        end

        def visibility_private_line?(stripped)
          stripped.match?(/\A(private|protected)(?:\s+#.*)?\z/)
        end

        def visibility_public_line?(stripped)
          stripped.match?(/\Apublic(?:\s+#.*)?\z/)
        end
      end
    end

    # Scans public controller action methods for model access without service or operation delegation.
    #
    # Flags methods that call ActiveRecord methods directly but contain no reference
    # to a +*Service+ / +*Operation+ entrypoint (+.new+ / +.call+), a namespaced domain operation
    # (+Domain::...::Name.call+ / +.new+, including legacy +::Operations::...+ paths), indicating the
    # data-layer interaction has not been routed through the layer.
    #
    # Method boundaries use standard 2-space Ruby indentation (RuboCop default).
    # Methods after a bare +private+ / +protected+ keyword are skipped. Single-line and endless
    # method definitions are out of scope for this checker.
    #
    # Usage:
    #   checker = Railsmith::ArchChecks::MissingServiceUsageChecker.new
    #   violations = checker.check(path: "app/controllers")
    class MissingServiceUsageChecker
      # *Service / *Operation entrypoints (namespaced tail allowed).
      SERVICE_OR_OPERATION_RE = /
        \b
        (?:[A-Z][A-Za-z0-9]*::)*
        [A-Z][A-Za-z0-9]*(?:Service|Operation)
        (?:::[A-Z][A-Za-z0-9]*)*
        \.(?:new|call)
        \b
      /x

      # Domain operations from the generator: legacy +...+::Operations::...+ (e.g. +Billing::Operations::Invoices::Create.call+).
      DOMAIN_OPERATION_RE = /
        \b
        (?:[A-Z][A-Za-z0-9]*::)+
        Operations::
        (?:[A-Z][A-Za-z0-9]*::)*
        [A-Z][A-Za-z0-9]*
        \.(?:new|call)
        \b
      /x

      # 1.1.0+ layout: +Domain::Module::Operation.call+ with no +Operations+ segment (three+ constants).
      FLAT_DOMAIN_OPERATION_RE = /
        \b
        (?:[A-Z][A-Za-z0-9]*::){2,}
        [A-Z][A-Za-z0-9]*
        \.(?:new|call)
        \b
      /x

      # @param path [String] directory to scan (recursively for *_controller.rb files)
      # @return [Array<Violation>]
      def check(path:)
        Dir.glob(File.join(path, "**", "*_controller.rb"))
           .flat_map { |file| check_file(file) }
      end

      # @param file [String] path to a single Ruby source file
      # @return [Array<Violation>]
      def check_file(file)
        lines = File.readlines(file, chomp: true)
        extract_action_methods(lines).filter_map { |method| method_violation(file, method) }
      end

      private

      def method_violation(file, method)
        return if method_uses_service?(method)
        return unless method_accesses_model?(method)

        Violation.new(
          :missing_service_usage,
          file,
          method[:start],
          "Action `#{method[:name]}` accesses models without delegating to a service class",
          :warn
        )
      end

      def extract_action_methods(lines)
        ControllerActionMethodExtractor.extract(lines)
      end

      def method_uses_service?(method)
        method[:body].any? do |line|
          SERVICE_OR_OPERATION_RE.match?(line) ||
            DOMAIN_OPERATION_RE.match?(line) ||
            FLAT_DOMAIN_OPERATION_RE.match?(line)
        end
      end

      def method_accesses_model?(method)
        method[:body].any? do |line|
          next false if line.start_with?("#")

          line.scan(DirectModelAccessChecker::DETECT_RE).any? do |class_name, _method_name|
            root = class_name.split("::").first
            !DirectModelAccessChecker::NON_MODEL_CLASSES.include?(root)
          end
        end
      end
    end
  end
end
