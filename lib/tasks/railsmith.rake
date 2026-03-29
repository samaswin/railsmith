# frozen_string_literal: true

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

    status = Railsmith::ArchChecks::Cli.run
    exit status unless status.zero?
  end
end
