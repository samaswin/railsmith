# frozen_string_literal: true

require_relative "lib/railsmith/version"

railsmith_gem_file_list = lambda do
  gemspec = File.basename(__FILE__)
  IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f == ".ruby-version" ||
        f == ".tool-versions" ||
        f.start_with?(*%w[bin/ Gemfile gemfiles/ .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
end

Gem::Specification.new do |spec|
  spec.name = "railsmith"
  spec.version = Railsmith::VERSION
  spec.authors = ["samaswin"]
  spec.email = ["samaswin@users.noreply.github.com"]

  spec.summary = "All-in-one service layer conventions for Rails."
  spec.description = "Railsmith provides service-layer architecture primitives " \
                     "for domain routing, CRUD/bulk operations, and structured results."
  spec.homepage = "https://github.com/samaswin/railsmith"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = railsmith_gem_file_list.call
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"
  spec.add_dependency "railties", ">= 7.0", "< 9.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
