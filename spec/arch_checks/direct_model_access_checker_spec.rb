# frozen_string_literal: true

require "spec_helper"
require "railsmith/arch_checks"
require "tempfile"
require "tmpdir"
require "fileutils"

RSpec.describe Railsmith::ArchChecks::DirectModelAccessChecker do
  subject(:checker) { described_class.new }

  let(:fixtures_root) { File.expand_path("../fixtures/controllers", __dir__) }
  let(:clean_file)      { File.join(fixtures_root, "clean_controller.rb") }
  let(:violations_file) { File.join(fixtures_root, "with_violations_controller.rb") }
  let(:medium_path)     { File.join(fixtures_root, "medium") }

  # ── Fixture-based detector tests ──────────────────────────────────────────

  describe "#check_file on a clean controller" do
    subject(:violations) { checker.check_file(clean_file) }

    it "returns no violations" do
      expect(violations).to be_empty
    end
  end

  describe "#check_file on a controller with violations" do
    subject(:violations) { checker.check_file(violations_file) }

    it "finds at least one violation" do
      expect(violations).not_to be_empty
    end

    it "flags User.all in the index action" do
      expect(violations).to include(
        have_attributes(rule: :direct_model_access, message: /User\.all/)
      )
    end

    it "flags User.find in the show action" do
      expect(violations).to include(
        have_attributes(rule: :direct_model_access, message: /User\.find/)
      )
    end

    it "flags Post.where in the create action" do
      expect(violations).to include(
        have_attributes(rule: :direct_model_access, message: /Post\.where/)
      )
    end

    it "flags Comment.count in the mixed action" do
      expect(violations).to include(
        have_attributes(rule: :direct_model_access, message: /Comment\.count/)
      )
    end

    it "flags User.find in the private dangerous_helper method" do
      expect(violations).to include(
        have_attributes(
          rule: :direct_model_access,
          file: violations_file,
          line: 51,
          message: /User\.find/
        )
      )
    end

    it "assigns :warn severity to every violation" do
      expect(violations.map(&:severity).uniq).to eq([:warn])
    end

    it "records the correct file path on each violation" do
      expect(violations.map(&:file).uniq).to eq([violations_file])
    end

    it "records 1-based line numbers" do
      expect(violations.map(&:line)).to all(be_a(Integer) & be_positive)
    end
  end

  # ── Exclusion-list tests ──────────────────────────────────────────────────

  describe "excluded non-model classes" do
    {
      "Rails.application" => "Rails.where",
      "Time.now" => "Time.all",
      "JSON.parse" => "JSON.create",
      "I18n.locale" => "I18n.find"
    }.each do |description, snippet|
      it "does not flag #{description}" do
        with_temp_controller(snippet) do |file|
          expect(checker.check_file(file)).to be_empty
        end
      end
    end
  end

  # ── Pattern boundary tests ────────────────────────────────────────────────

  describe "method name boundary detection" do
    it "does not flag User.finder (partial method name)" do
      with_temp_controller("@x = User.finder") do |file|
        expect(checker.check_file(file)).to be_empty
      end
    end

    it "flags User.find (exact method name)" do
      with_temp_controller("@user = User.find(1)") do |file|
        expect(checker.check_file(file)).not_to be_empty
      end
    end

    it "flags namespaced models like Catalog::Item.where(...)" do
      with_temp_controller("@items = Catalog::Item.where(active: true)") do |file|
        violations = checker.check_file(file)
        expect(violations).to include(have_attributes(message: /Catalog::Item\.where/))
      end
    end

    it "does not flag comment lines" do
      with_temp_controller("# @user = User.find(params[:id])") do |file|
        expect(checker.check_file(file)).to be_empty
      end
    end
  end

  # ── #check (directory scan) ───────────────────────────────────────────────

  describe "#check" do
    it "scans all *_controller.rb files in the given directory" do
      violations = checker.check(path: fixtures_root)
      expect(violations).not_to be_empty
    end

    it "returns no violations for a clean directory" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(clean_file, File.join(dir, "clean_controller.rb"))
        expect(checker.check(path: dir)).to be_empty
      end
    end
  end

  # ── Scale sanity test ─────────────────────────────────────────────────────

  describe "medium fixture set" do
    it "runs without errors and returns a bounded result" do
      violations = checker.check(path: medium_path)
      expect(violations).to be_a(Array)
      # Sanity: medium set has ~5 controllers; violations should be reasonable
      expect(violations.size).to be_between(1, 30)
    end

    it "finds no violations in the all-clean beta and epsilon controllers" do
      clean_files = [
        File.join(medium_path, "beta_controller.rb"),
        File.join(medium_path, "epsilon_controller.rb")
      ]
      violations = clean_files.flat_map { |f| checker.check_file(f) }
      expect(violations).to be_empty
    end
  end

  # ── Helper ───────────────────────────────────────────────────────────────

  def with_temp_controller(body_line)
    Tempfile.create(["test", "_controller.rb"]) do |f|
      f.write("# frozen_string_literal: true\n")
      f.write("class TestController < ApplicationController\n")
      f.write("  def action\n")
      f.write("    #{body_line}\n")
      f.write("  end\n")
      f.write("end\n")
      f.flush
      yield f.path
    end
  end
end
