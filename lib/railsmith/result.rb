# frozen_string_literal: true

module Railsmith
  # An immutable success/failure wrapper with a stable serialization contract.
  class Result
    def self.success(value: nil, meta: nil)
      new(success: true, value:, error: nil, meta: meta || {})
    end

    def self.failure(code: nil, message: nil, details: nil, error: nil, meta: nil)
      normalized_error =
        error ||
        Errors::ErrorPayload.new(
          code: code || :unexpected,
          message: message || "Unexpected error",
          details:
        )

      new(success: false, value: nil, error: normalized_error, meta: meta || {})
    end

    private_class_method :new

    def initialize(success:, value:, error:, meta:)
      @success = success ? true : false
      @value = value
      @error = error
      @meta = meta || {}
      freeze
    end

    def success?
      @success
    end

    def failure?
      !success?
    end

    attr_reader :value, :error, :meta

    def code
      return nil if error.nil?

      error.code
    end

    def to_h
      if success?
        { success: true, value:, meta: }
      else
        { success: false, error: error.to_h, meta: }
      end
    end

    def as_json(*)
      to_h
    end
  end
end
