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
      "not_found" => :not_found,
      "conflict" => :conflict,
      "unauthorized" => :unauthorized,
      "unexpected" => :internal_server_error
    }.freeze

    if defined?(ActiveSupport::Concern)
      extend ActiveSupport::Concern

      included do
        next unless respond_to?(:rescue_from)

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

    # Builds a {Railsmith::Context} seeded with the incoming request's id,
    # so every service invoked from this controller shares the same
    # +request_id+ as the +X-Request-Id+ header ActionDispatch observed.
    #
    # @example Propagating the request id into a service call
    #   class OrdersController < ApplicationController
    #     include Railsmith::ControllerHelpers
    #
    #     def create
    #       result = OrderService.call!(
    #         action: :create,
    #         params: { attributes: order_params },
    #         context: railsmith_context(domain: :commerce, actor_id: current_user.id)
    #       )
    #       render json: result.value, status: :created
    #     end
    #   end
    #
    # @param domain [Symbol, String, nil] bounded-context key for the call
    # @param extras [Hash] arbitrary extra keys (actor_id, tenant_id, etc.)
    # @return [Railsmith::Context]
    def railsmith_context(domain: nil, **extras)
      request_id = extras.delete(:request_id)
      request_id ||= request.request_id if respond_to?(:request) && request.respond_to?(:request_id)

      Railsmith::Context.new(
        domain: domain,
        request_id: request_id,
        **extras
      )
    end
  end
end
