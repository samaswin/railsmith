# frozen_string_literal: true

require "spec_helper"
require "railsmith/arch_checks"

RSpec.describe Railsmith::ArchReport do
  let(:violation_a) do
    Railsmith::ArchChecks::Violation.new(
      :direct_model_access,
      "app/controllers/users_controller.rb",
      12,
      "Direct model access: `User.find` — route through a service instead",
      :warn
    )
  end

  let(:violation_b) do
    Railsmith::ArchChecks::Violation.new(
      :missing_service_usage,
      "app/controllers/posts_controller.rb",
      8,
      "Action `index` accesses models without delegating to a service class",
      :warn
    )
  end

  let(:checked_files) do
    %w[
      app/controllers/users_controller.rb
      app/controllers/posts_controller.rb
    ]
  end

  # ── Clean report ──────────────────────────────────────────────────────────

  describe "with no violations" do
    subject(:report) { described_class.new(violations: [], checked_files: checked_files) }

    it { is_expected.to be_clean }
    specify { expect(report.violation_count).to eq(0) }

    describe "#as_text" do
      subject(:text) { report.as_text }

      it "includes the header" do
        expect(text).to include("Railsmith Architecture Check")
      end

      it "reports the file count and zero violations" do
        expect(text).to include("Checked 2 files — 0 violations found")
      end

      it "ends with an OK message" do
        expect(text).to include("OK — no violations found.")
      end
    end

    describe "#as_json" do
      subject(:parsed) { JSON.parse(report.as_json) }

      it "marks clean as true" do
        expect(parsed.dig("summary", "clean")).to be true
      end

      it "reports zero violations" do
        expect(parsed.dig("summary", "violation_count")).to eq(0)
      end

      it "has an empty violations array" do
        expect(parsed["violations"]).to eq([])
      end

      it "reports the checked file count" do
        expect(parsed.dig("summary", "checked_files")).to eq(2)
      end

      it "includes fail_on_arch_violations in summary (default false)" do
        expect(parsed.dig("summary", "fail_on_arch_violations")).to be false
      end
    end
  end

  # ── Report with violations ────────────────────────────────────────────────

  describe "with violations" do
    subject(:report) do
      described_class.new(violations: [violation_a, violation_b], checked_files: checked_files)
    end

    it { is_expected.not_to be_clean }
    specify { expect(report.violation_count).to eq(2) }

    describe "#as_text — snapshot" do
      subject(:text) { report.as_text }

      it "includes the header and separator" do
        expect(text).to include("Railsmith Architecture Check")
        expect(text).to include("=" * 30)
      end

      it "shows the summary line with file and violation counts" do
        expect(text).to include("Checked 2 files — 2 violations found")
      end

      it "includes each violation's file and line" do
        expect(text).to include("app/controllers/users_controller.rb:12")
        expect(text).to include("app/controllers/posts_controller.rb:8")
      end

      it "includes the severity tag and rule for each violation" do
        expect(text).to include("[WARN] direct_model_access:")
        expect(text).to include("[WARN] missing_service_usage:")
      end

      it "includes each violation's message" do
        expect(text).to include("Direct model access: `User.find`")
        expect(text).to include("Action `index` accesses models")
      end

      it "ends with the warn-only footer when fail-on is off" do
        expect(text).to include("Violations listed above are warnings only")
      end

      it "ends with the fail-on footer when fail-on is enabled" do
        report = described_class.new(
          violations: [violation_a, violation_b],
          checked_files: checked_files,
          fail_on_arch_violations: true
        )
        expect(report.as_text).to include("non-zero exit (fail-on mode is enabled)")
      end
    end

    describe "#as_json — snapshot" do
      subject(:parsed) { JSON.parse(report.as_json) }

      it "marks clean as false" do
        expect(parsed.dig("summary", "clean")).to be false
      end

      it "includes fail_on_arch_violations in summary" do
        expect(parsed.dig("summary", "fail_on_arch_violations")).to be false
      end

      it "reports 2 violations" do
        expect(parsed.dig("summary", "violation_count")).to eq(2)
      end

      it "includes both violation objects" do
        rules = parsed["violations"].map { |v| v["rule"] }
        expect(rules).to contain_exactly("direct_model_access", "missing_service_usage")
      end

      it "serializes all violation fields" do
        v = parsed["violations"].first
        expect(v.keys).to contain_exactly("rule", "file", "line", "message", "severity")
      end

      it "serializes symbols as strings" do
        severities = parsed["violations"].map { |v| v["severity"] }
        expect(severities).to all(eq("warn"))
      end

      it "preserves line numbers as integers" do
        lines = parsed["violations"].map { |v| v["line"] }
        expect(lines).to all(be_a(Integer))
      end
    end
  end

  # ── Edge cases ────────────────────────────────────────────────────────────

  describe "edge cases" do
    it "accepts nil for checked_files and defaults to empty array" do
      report = described_class.new(violations: [], checked_files: nil)
      expect(report.checked_files).to eq([])
    end

    it "uses singular 'file' and 'violation' when counts are 1" do
      report = described_class.new(
        violations: [violation_a],
        checked_files: ["app/controllers/users_controller.rb"]
      )
      expect(report.as_text).to include("Checked 1 file — 1 violation found")
    end

    it "#to_h returns a plain Hash (not JSON string)" do
      report = described_class.new(violations: [violation_a], checked_files: checked_files)
      expect(report.to_h).to be_a(Hash)
    end
  end
end
