# frozen_string_literal: true

require "rails/generators"

module Railsmith
  module Generators
    # Installs initializer and base service directories in host app.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "railsmith.rb", "config/initializers/railsmith.rb"
      end

      def create_service_directories
        empty_directory "app/services"
        empty_directory "app/services/operations"
      end
    end
  end
end
