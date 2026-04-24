# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in railsmith.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"
gem "simplecov", require: false

gem "timecop", "~> 0.9"

gem "appraisal", "~> 2.5"

gem "rubocop", "~> 1.21"

gem "actionpack", ">= 7.0", "< 9.0"
gem "activerecord", ">= 7.0", "< 9.0"
# parallel 2.1+ requires Ruby >= 3.3; CI includes Ruby 3.2.
gem "parallel", "< 2.1.0" if RUBY_VERSION < "3.3"

# sqlite3 2.9+ requires Ruby >= 3.2; CI still runs Rails 7.0/7.1 on 3.1.
gem "sqlite3", "~> 1.4" if RUBY_VERSION < "3.2"
gem "sqlite3", ">= 2.1" if RUBY_VERSION >= "3.2"

# Ruby 3.1 compatibility: transitive deps that require >= 3.2 in newer versions.
# These pins are not needed on 3.2+ but don't hurt — they allow any version on newer Rubies.
if RUBY_VERSION < "3.2"
  gem "connection_pool", "< 3"
  gem "erb", "< 5"
  gem "nokogiri", "< 1.19"
  gem "zeitwerk", "< 2.7"
end
