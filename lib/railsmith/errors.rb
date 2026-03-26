# frozen_string_literal: true

module Railsmith
  # Normalized builders for failure payloads.
  module Errors
    # A structured error payload used in failure results.
    class ErrorPayload
      attr_reader :code, :message, :details

      def initialize(code:, message:, details: nil)
        @code = code.to_s
        @message = message.to_s
        @details = details
      end

      def to_h
        payload = { code:, message: }
        payload[:details] = details unless details.nil?
        payload
      end

      def as_json(*)
        to_h
      end
    end

    class << self
      def validation_error(message: "Validation failed", details: nil)
        ErrorPayload.new(code: :validation_error, message:, details: details || {})
      end

      def not_found(message: "Not found", details: nil)
        ErrorPayload.new(code: :not_found, message:, details: details || {})
      end

      def conflict(message: "Conflict", details: nil)
        ErrorPayload.new(code: :conflict, message:, details: details || {})
      end

      def unauthorized(message: "Unauthorized", details: nil)
        ErrorPayload.new(code: :unauthorized, message:, details: details || {})
      end

      def unexpected(message: "Unexpected error", details: nil)
        ErrorPayload.new(code: :unexpected, message:, details: details)
      end
    end
  end
end
