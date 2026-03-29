# frozen_string_literal: true

require "json"

module Railsmith
  # Formats static-analysis violations for human and machine consumption.
  #
  # Supports two output formats:
  # - +as_text+ — multi-line, human-readable report for local runs.
  # - +as_json+ — single JSON object for CI tooling and log aggregation.
  #
  # Usage:
  #   report = Railsmith::ArchReport.new(violations: violations, checked_files: files)
  #   puts report.as_text
  #   # or
  #   puts report.as_json
  class ArchReport
    SEPARATOR = ("=" * 30).freeze

    attr_reader :violations, :checked_files

    # @param violations [Array<ArchChecks::Violation>]
    # @param checked_files [Array<String>] paths that were analysed
    def initialize(violations:, checked_files: [])
      @violations = Array(violations)
      @checked_files = Array(checked_files)
    end

    # @return [Boolean] true when no violations were found
    def clean?
      violations.empty?
    end

    # @return [Integer]
    def violation_count
      violations.size
    end

    # Multi-line, human-readable text report.
    # @return [String]
    def as_text
      lines = ["Railsmith Architecture Check", SEPARATOR, summary_line]
      unless violations.empty?
        lines << ""
        violations.each { |v| lines.concat(violation_lines(v)) }
        lines << ""
      end
      lines << footer_line
      lines.join("\n")
    end

    # Single JSON object suitable for CI log parsing.
    # @return [String]
    def as_json
      JSON.generate(to_h)
    end

    # @return [Hash]
    def to_h
      { summary: summary_hash, violations: violations.map { |v| violation_to_h(v) } }
    end

    private

    def summary_hash
      { checked_files: checked_files.size, violation_count: violations.size, clean: clean? }
    end

    def violation_to_h(violation)
      {
        rule: violation.rule.to_s,
        file: violation.file,
        line: violation.line,
        message: violation.message,
        severity: violation.severity.to_s
      }
    end

    def summary_line
      file_word      = checked_files.size == 1 ? "file" : "files"
      violation_word = violations.size    == 1 ? "violation" : "violations"
      "Checked #{checked_files.size} #{file_word} — #{violations.size} #{violation_word} found"
    end

    def footer_line
      clean? ? "OK — no violations found." : "Violations listed above are warnings only (warn-only mode)."
    end

    def violation_lines(violation)
      [
        "  #{violation.file}:#{violation.line}",
        "    [#{violation.severity.to_s.upcase}] #{violation.rule}: #{violation.message}"
      ]
    end
  end
end
