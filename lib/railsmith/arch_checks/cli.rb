# frozen_string_literal: true

module Railsmith
  module ArchChecks
    # Runs architecture checks driven by ENV and prints a report to +output+.
    # Returns 0 when the scan is clean or warn-only mode allows violations, and 1
    # when fail-on is enabled and violations exist.
    class Cli
      def self.run(env: ENV, output: $stdout, warn_proc: Kernel.method(:warn))
        new(env: env, output: output, warn_proc: warn_proc).run
      end

      def initialize(env:, output:, warn_proc:)
        @env = env
        @output = output
        @warn_proc = warn_proc
      end

      # @return [Integer] 0 or 1
      def run
        format_sym = normalized_format
        paths = paths_list
        fail_on = fail_on_violations?
        checked_files, violations = scan(paths)
        report = arch_report(violations, checked_files, fail_on)
        emit_report(format_sym, report)
        status_for(fail_on, report)
      end

      private

      def arch_report(violations, checked_files, fail_on)
        Railsmith::ArchReport.new(
          violations: violations,
          checked_files: checked_files,
          fail_on_arch_violations: fail_on
        )
      end

      def normalized_format
        raw = @env.fetch("RAILSMITH_FORMAT", "text").downcase.strip
        unless %w[text json].include?(raw)
          @warn_proc.call("railsmith:arch_check — invalid RAILSMITH_FORMAT=#{raw.inspect}, using text")
          raw = "text"
        end
        raw.to_sym
      end

      def paths_list
        @env.fetch("RAILSMITH_PATHS", "app/controllers").split(",").map(&:strip)
      end

      def fail_on_violations?
        strict = @env.fetch("RAILSMITH_FAIL_ON_ARCH_VIOLATIONS", "").strip.downcase
        if %w[true 1 yes].include?(strict)
          true
        elsif strict.empty?
          Railsmith.configuration.fail_on_arch_violations
        else
          false
        end
      end

      def scan(paths)
        checkers = [
          Railsmith::ArchChecks::DirectModelAccessChecker.new,
          Railsmith::ArchChecks::MissingServiceUsageChecker.new
        ]
        paths.each_with_object([[], []]) do |path, (checked_files, violations)|
          next unless Dir.exist?(path)

          checked_files.concat(Dir.glob(File.join(path, "**", "*_controller.rb")))
          checkers.each { |checker| violations.concat(checker.check(path: path)) }
        end
      end

      def emit_report(format_sym, report)
        out_string = format_sym == :json ? report.as_json : report.as_text
        @output.puts out_string
      end

      def status_for(fail_on, report)
        fail_on && !report.clean? ? 1 : 0
      end
    end
  end
end
