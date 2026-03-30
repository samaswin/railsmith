# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in railsmith.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "timecop", "~> 0.9"

gem "rubocop", "~> 1.21"

gem "activerecord", ">= 7.0", "< 9.0"
gem "sqlite3", ">= 2.1"

# Ruby 3.1 compatibility: transitive deps that require >= 3.2 in newer versions.
# These pins are not needed on 3.2+ but don't hurt — they allow any version on newer Rubies.
if RUBY_VERSION < "3.2"
  gem "connection_pool", "< 3"
  gem "erb", "< 5"
  gem "nokogiri", "< 1.19"
  gem "zeitwerk", "< 2.7"
end
