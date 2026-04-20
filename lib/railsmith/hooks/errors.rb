# frozen_string_literal: true

module Railsmith
  module Hooks
    # Base class for all hook-related errors. Inherits directly from
    # +StandardError+ to avoid a load-order dependency on +Railsmith::Error+,
    # which is defined at the tail of +lib/railsmith.rb+.
    class Error < StandardError; end

    # Raised when an +around+ hook returns without ever invoking the wrapped
    # action. This catches the common mistake of forgetting to call +action.call+
    # (or whatever the block argument is named) inside an around hook body.
    class AroundHookNotYieldedError < Error
      def initialize(service:, action:, hook_name: nil)
        label = hook_name ? "#{hook_name} " : ""
        super(
          "around hook #{label}on #{service}##{action} returned without " \
          "invoking the wrapped action. An around hook must call the " \
          "yielded action block (e.g. `action.call`)."
        )
      end
    end
  end
end
