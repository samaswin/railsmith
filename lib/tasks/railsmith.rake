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

  desc <<~DESC
    List all Railsmith::Pipeline subclasses and their declared steps.

    Requires the Rails environment to be loaded so all pipeline constants are available.
    Run as: rake railsmith:pipelines
  DESC
  task :pipelines => :environment do
    require "railsmith"
    require "railsmith/pipeline"

    pipelines = ObjectSpace.each_object(Class).select { |klass|
      klass < Railsmith::Pipeline && klass.name
    }.sort_by(&:name)

    if pipelines.empty?
      puts "No Railsmith pipelines found."
      next
    end

    pipelines.each do |pipeline|
      puts "\n#{pipeline.name}"
      puts "  (no steps declared)" if pipeline.step_definitions.empty?

      pipeline.step_definitions.each_with_index do |step, idx|
        svc_name   = step.service.respond_to?(:name) ? step.service.name : step.service.to_s
        parts      = ["  step :#{step.name}", "service: #{svc_name}", "action: :#{step.action}"]
        parts      << "rollback: :#{step.rollback}" if step.rollback.is_a?(Symbol)
        parts      << "rollback: <proc>" if step.rollback.is_a?(Proc)
        parts      << "if: ..." if step.condition && step.polarity == :if
        parts      << "unless: ..." if step.condition && step.polarity == :unless
        puts parts.join(", ")
      end
    end

    puts ""
  end
end
