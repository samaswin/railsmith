# frozen_string_literal: true

require_relative "railsmith/version"
require_relative "railsmith/configuration"

# Entry point for global gem configuration and loading.
module Railsmith
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
