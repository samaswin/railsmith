# frozen_string_literal: true

require_relative "railsmith/version"
require_relative "railsmith/configuration"
require_relative "railsmith/errors"
require_relative "railsmith/result"
require_relative "railsmith/deep_dup"
require_relative "railsmith/context"
require_relative "railsmith/domain_context"
require_relative "railsmith/instrumentation"
require_relative "railsmith/cross_domain_guard"
require_relative "railsmith/cross_domain_warning_formatter"
require_relative "railsmith/failure"
require_relative "railsmith/hooks"
require_relative "railsmith/base_service"
require_relative "railsmith/pipeline"
require_relative "railsmith/controller_helpers"
require_relative "railsmith/async_enqueuers"
require_relative "railsmith/async_nested_write_job"

require_relative "railsmith/railtie" if defined?(Rails::Railtie)

# Entry point for global gem configuration and loading.
module Railsmith
  class Error < StandardError; end

  # Raised when an association is declared with +async: true+ but
  # +Railsmith.configuration.async_job_class+ has not been set. The service
  # layer cannot enqueue a nested write without a configured ActiveJob class.
  class AsyncNotConfiguredError < Error; end

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
