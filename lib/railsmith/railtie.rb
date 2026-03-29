# frozen_string_literal: true

module Railsmith
  # Loads Rake tasks when the gem is used inside a Rails application.
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/railsmith.rake", __dir__)
    end
  end
end
