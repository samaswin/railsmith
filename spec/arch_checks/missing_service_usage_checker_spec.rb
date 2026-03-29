# frozen_string_literal: true

require "spec_helper"
require "railsmith/arch_checks"
require "tempfile"
require "tmpdir"
require "fileutils"

RSpec.describe Railsmith::ArchChecks::MissingServiceUsageChecker do
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

    it "flags the index action (User.all, no service)" do
      expect(violations).to include(
        have_attributes(rule: :missing_service_usage, message: /`index`/)
      )
    end

    it "flags the show action (User.find, no service)" do
      expect(violations).to include(
        have_attributes(rule: :missing_service_usage, message: /`show`/)
      )
    end

    it "flags the create action (Post.where, no service)" do
      expect(violations).to include(
        have_attributes(rule: :missing_service_usage, message: /`create`/)
      )
    end

    it "does NOT flag the mixed action (Comment.count but service present)" do
      names = violations.map(&:message)
      expect(names).not_to include(match(/`mixed`/))
    end

    it "does NOT flag the clean action (service only)" do
      names = violations.map(&:message)
      expect(names).not_to include(match(/`clean`/))
    end

    it "does NOT flag the private dangerous_helper action" do
      expect(violations.map(&:message)).not_to include(match(/dangerous_helper/))
    end

    it "assigns :warn severity to every violation" do
      expect(violations.map(&:severity).uniq).to eq([:warn])
    end

    it "records the line number of the def keyword" do
      expect(violations.map(&:line)).to all(be_a(Integer) & be_positive)
    end
  end

  # ── Service detection variants ────────────────────────────────────────────

  describe "service call detection" do
    it "accepts SomeService.new(...) as service usage" do
      with_temp_controller(<<~RUBY) do |file|
        result = UserService.new(context: ctx).list
        @users = result.value
      RUBY
        expect(checker.check_file(file)).to be_empty
      end
    end

    it "accepts SomeService.call(...) as service usage" do
      with_temp_controller(<<~RUBY) do |file|
        result = UserService.call(context: ctx, id: params[:id])
        @user = result.value
      RUBY
        expect(checker.check_file(file)).to be_empty
      end
    end

    it "accepts namespaced services like Billing::InvoiceService.new" do
      with_temp_controller(<<~RUBY) do |file|
        @invoice = Invoice.find(params[:id])
        result   = Billing::InvoiceService.new(context: ctx).process(@invoice)
      RUBY
        expect(checker.check_file(file)).to be_empty
      end
    end

    it "accepts domain operation entrypoints under ::Operations::" do
      with_temp_controller(<<~RUBY) do |file|
        @user = User.find(params[:id])
        result = Billing::Operations::Invoices::Create.call(params: { user: @user }, context: ctx)
      RUBY
        expect(checker.check_file(file)).to be_empty
      end
    end

    it "accepts *Operation.call delegation" do
      with_temp_controller(<<~RUBY) do |file|
        @post = Post.find(params[:id])
        result = PublishPostOperation.call(params: { post: @post }, context: ctx)
      RUBY
        expect(checker.check_file(file)).to be_empty
      end
    end

    it "flags an action with model access and no service" do
      with_temp_controller("@user = User.find(params[:id])") do |file|
        violations = checker.check_file(file)
        expect(violations).not_to be_empty
        expect(violations.first.rule).to eq(:missing_service_usage)
      end
    end

    it "does NOT flag an action with neither model access nor service" do
      with_temp_controller("render :index") do |file|
        expect(checker.check_file(file)).to be_empty
      end
    end
  end

  # ── Method boundary tests ─────────────────────────────────────────────────

  describe "method boundary extraction" do
    it "reports the def line number of the offending method" do
      source = <<~RUBY
        class TestController < ApplicationController
          def safe
            result = UserService.new(context: ctx).list
            @users = result.value
          end

          def unsafe
            @users = User.all
          end
        end
      RUBY

      Tempfile.create(["bound", "_controller.rb"]) do |f|
        f.write(source)
        f.flush
        violations = checker.check_file(f.path)
        expect(violations.size).to eq(1)
        expect(violations.first.message).to match(/`unsafe`/)
        # "def unsafe" is on line 7 in the heredoc above
        expect(violations.first.line).to eq(7)
      end
    end

    it "handles multiple nested blocks inside a method without mis-closing" do
      with_temp_controller(<<~RUBY) do |file|
        if params[:id]
          if params[:format]
            @user = User.find(params[:id])
          end
        end
      RUBY
        violations = checker.check_file(file)
        expect(violations).not_to be_empty
        expect(violations.first.rule).to eq(:missing_service_usage)
      end
    end
  end

  # ── #check (directory scan) ───────────────────────────────────────────────

  describe "#check" do
    it "scans all *_controller.rb files in the given directory" do
      violations = checker.check(path: fixtures_root)
      expect(violations).not_to be_empty
    end

    it "returns no violations for a directory of clean controllers" do
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
      expect(violations.size).to be_between(0, 20)
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

  def with_temp_controller(body)
    Tempfile.create(["test", "_controller.rb"]) do |f|
      f.write("# frozen_string_literal: true\n")
      f.write("class TestController < ApplicationController\n")
      f.write("  def action\n")
      body.each_line { |line| f.write("    #{line}") }
      f.write("\n  end\n")
      f.write("end\n")
      f.flush
      yield f.path
    end
  end
end
