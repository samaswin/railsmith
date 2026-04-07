# frozen_string_literal: true

module Railsmith
  # Raised by {BaseService.call!} when the service returns a failure result.
  # Carries the original Result so callers (or rescue_from handlers) can inspect
  # the structured error without parsing a string message.
  class Failure < StandardError
    attr_reader :result

    def initialize(result)
      @result = result
      super(result.error&.message || "Service call failed")
    end

    def code
      result.code
    end

    def error
      result.error
    end

    def meta
      result.meta
    end
  end
end
