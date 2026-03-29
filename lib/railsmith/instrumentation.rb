# frozen_string_literal: true

module Railsmith
  # Lightweight instrumentation hook layer for domain-tagged service events.
  #
  # Uses ActiveSupport::Notifications when available so events slot naturally
  # into Rails instrumentation pipelines. Falls back to plain Ruby subscribers
  # for non-Rails contexts.
  #
  # Example (plain Ruby subscriber):
  #   Railsmith::Instrumentation.subscribe("service.call") do |event, payload|
  #     Rails.logger.info "[#{payload[:domain]}] #{payload[:service]}##{payload[:action]}"
  #   end
  module Instrumentation
    EVENT_NAMESPACE = "railsmith"

    class << self
      # Emit a domain-tagged event, yielding to the wrapped block if given.
      # Payload is always a Hash; a :domain key is expected for domain tagging.
      # Always dispatches to plain Ruby subscribers; also emits to
      # ActiveSupport::Notifications when available for Rails integration.
      def instrument(event_name, payload = {}, &block)
        full_name = "#{event_name}.#{EVENT_NAMESPACE}"
        result = nil
        if active_support_notifications?
          ActiveSupport::Notifications.instrument(full_name, payload) { result = block&.call }
        else
          result = block&.call
        end
        dispatch(full_name, payload)
        result
      end

      # Register a plain Ruby subscriber for events matching an optional prefix.
      # Subscriber is called with (event_name, payload).
      def subscribe(pattern = nil, &block)
        subscribers << { pattern: pattern, handler: block }
      end

      # Remove all plain Ruby subscribers (useful in tests).
      def reset!
        @subscribers = []
      end

      private

      def subscribers
        @subscribers ||= []
      end

      def active_support_notifications?
        defined?(ActiveSupport::Notifications)
      end

      def dispatch(event_name, payload)
        subscribers.each do |sub|
          next if sub[:pattern] && !event_name.start_with?(sub[:pattern])

          sub[:handler].call(event_name, payload)
        end
      end
    end
  end
end
