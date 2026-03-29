# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :railsmith do
  desc <<~DESC
    Run Railsmith architecture checks on controller files and print a report.

    Configuration via environment variables:
      RAILSMITH_PATHS                    Comma-separated controller directories (default: app/controllers)
      RAILSMITH_FORMAT                   Output format: "text" or "json" (default: text; invalid values fall back to text with a warning)
      RAILSMITH_FAIL_ON_ARCH_VIOLATIONS  If set to "true", "1", or "yes", exit 1 when violations exist (overrides config)

    Exit behaviour:
      Exits 0 in warn-only mode (the default) regardless of violations.
      Set +Railsmith.configuration.fail_on_arch_violations = true+ or
      +RAILSMITH_FAIL_ON_ARCH_VIOLATIONS=true+ to exit 1 when violations are found.
  DESC
  task :arch_check do
    require "railsmith"
    require "railsmith/arch_checks"

    paths_env = ENV.fetch("RAILSMITH_PATHS", "app/controllers")
    format_raw = ENV.fetch("RAILSMITH_FORMAT", "text").downcase.strip
    unless %w[text json].include?(format_raw)
      warn "railsmith:arch_check — invalid RAILSMITH_FORMAT=#{format_raw.inspect}, using text"
      format_raw = "text"
    end
    format = format_raw.to_sym
    paths  = paths_env.split(",").map(&:strip)
    config = Railsmith.configuration

    env_strict = ENV.fetch("RAILSMITH_FAIL_ON_ARCH_VIOLATIONS", "").strip.downcase
    fail_on_violations = if %w[true 1 yes].include?(env_strict)
                           true
                         elsif env_strict.empty?
                           config.fail_on_arch_violations
                         else
                           false
                         end

    checked_files = []
    violations    = []

    checkers = [
      Railsmith::ArchChecks::DirectModelAccessChecker.new,
      Railsmith::ArchChecks::MissingServiceUsageChecker.new
    ]

    paths.each do |path|
      next unless Dir.exist?(path)

      files = Dir.glob(File.join(path, "**", "*_controller.rb"))
      checked_files.concat(files)

      checkers.each do |checker|
        violations.concat(checker.check(path: path))
      end
    end

    report = Railsmith::ArchReport.new(violations: violations, checked_files: checked_files)
    output = format == :json ? report.as_json : report.as_text
    $stdout.puts output

    exit 1 if fail_on_violations && !report.clean?
  end
end
# rubocop:enable Metrics/BlockLength
