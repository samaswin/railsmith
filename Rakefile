# frozen_string_literal: true

require "bundler/gem_tasks"

load File.expand_path("lib/tasks/railsmith.rake", __dir__)
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]
