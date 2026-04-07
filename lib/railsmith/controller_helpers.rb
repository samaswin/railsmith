# frozen_string_literal: true

module Railsmith
  # Include this concern in an ApplicationController (or a specific controller)
  # to get automatic JSON error responses when a service raises
  # {Railsmith::Failure}.
  #
  # @example
  #   class ApplicationController < ActionController::API
  #     include Railsmith::ControllerHelpers
  #   end
  #
  #   # In an action:
  #   UserService.call!(action: :create, params: ..., context: ...)
  #   # => on failure, renders JSON with the right HTTP status automatically
  module ControllerHelpers
    # Maps Railsmith error codes to HTTP status symbols understood by Rails'
    # +render json:, status:+.
    ERROR_STATUS_MAP = {
      "validation_error" => :unprocessable_entity,
      "not_found"        => :not_found,
      "conflict"         => :conflict,
      "unauthorized"     => :unauthorized,
      "unexpected"       => :internal_server_error
    }.freeze

    if defined?(ActiveSupport::Concern)
      extend ActiveSupport::Concern

      included do
        rescue_from Railsmith::Failure do |exception|
          error = exception.result.error
          status = Railsmith::ControllerHelpers::ERROR_STATUS_MAP.fetch(
            error&.code.to_s,
            :internal_server_error
          )
          render json: exception.result.to_h, status: status
        end
      end
    end
  end
end
