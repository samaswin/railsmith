# frozen_string_literal: true

module Railsmith
  module ArchChecks
    # Scans controller source files for direct ActiveRecord model access.
    #
    # Flags lines like +User.find(params[:id])+ or +Post.where(active: true)+
    # that bypass the service layer. The check is heuristic: it detects
    # CamelCase class names followed by common AR query/persistence methods,
    # excluding well-known non-model classes (Rails, Time, JSON, etc.).
    #
    # Usage:
    #   checker = Railsmith::ArchChecks::DirectModelAccessChecker.new
    #   violations = checker.check(path: "app/controllers")
    class DirectModelAccessChecker
      AR_METHODS = %w[
        find find_by find_by! find_or_create_by find_or_initialize_by
        where order select limit offset joins includes eager_load preload
        all first last count sum average minimum maximum
        create create! update update_all destroy destroy_all delete delete_all
        exists? any? none? many? pluck ids
      ].freeze

      # Well-known non-model CamelCase roots frequently seen in controllers.
      NON_MODEL_CLASSES = %w[
        Rails I18n Time Date DateTime ActiveRecord ApplicationRecord ActiveModel
        ActionController ApplicationController ActionDispatch AbstractController
        ActionView ActionMailer ActiveJob ActiveSupport ActiveStorage
        Integer Float String Hash Array Symbol Numeric BigDecimal
        File Dir IO URI URL Net HTTP JSON YAML CSV
        Logger Thread Fiber Mutex Proc Method Class Module Object BasicObject
      ].freeze

      AR_METHODS_PATTERN = AR_METHODS.map { |m| Regexp.escape(m) }.join("|")

      # Matches: CamelCase class name, dot, AR method, not followed by identifier chars.
      # The negative lookahead `(?=[^a-zA-Z0-9_]|$)` prevents `find` matching `finder`.
      DETECT_RE = /
        \b
        ([A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*)   (?# class name, possibly namespaced)
        \.
        (#{AR_METHODS_PATTERN})                          (?# AR method)
        (?=[^a-zA-Z0-9_]|$)                             (?# not followed by identifier chars)
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
        violations = []
        File.foreach(file).with_index(1) do |raw_line, lineno|
          line = raw_line.strip
          violations.concat(line_violations(file, lineno, line)) unless comment_line?(line)
        end
        violations
      end

      private

      def line_violations(file, lineno, line)
        line.scan(DETECT_RE).filter_map do |class_name, method_name|
          next if excluded_class?(class_name)

          build_violation(file, lineno, class_name, method_name)
        end
      end

      def build_violation(file, lineno, class_name, method_name)
        Violation.new(
          :direct_model_access,
          file,
          lineno,
          "Direct model access: `#{class_name}.#{method_name}` — route through a service instead",
          :warn
        )
      end

      def comment_line?(stripped)
        stripped.start_with?("#")
      end

      def excluded_class?(class_name)
        root = class_name.split("::").first
        NON_MODEL_CLASSES.include?(root)
      end
    end
  end
end
