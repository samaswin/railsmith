# frozen_string_literal: true

module Railsmith
  class BaseService
    # Handles nested association writes within service actions.
    #
    # All nested operations delegate to the associated service class, running
    # within the caller's open transaction so any failure triggers a full
    # rollback of parent + nested writes.
    #
    # Nested create flow (has_many / has_one):
    #   1. Parent record is already persisted
    #   2. For each declared association with nested params in the call's params:
    #      a. Inject parent FK into each item's attributes
    #      b. Delegate to associated service (create / update / destroy)
    #   3. Return success with parent record, or first failure (caller rolls back)
    #
    # Nested update semantics per item:
    #   - has id + attributes    → :update via associated service
    #   - has attributes only    → :create via associated service (FK injected)
    #   - has id + _destroy: true → :destroy via associated service
    #
    # Cascading destroy:
    #   dependent: :destroy  → calls associated service destroy for each child
    #   dependent: :nullify  → calls associated service update with FK set to nil
    #   dependent: :restrict → returns failure if any children exist
    #   dependent: :ignore   → does nothing (rely on DB constraints)
    #
    module NestedWriter
      require_relative "nested_writer/cascading_destroy"
      require_relative "nested_writer/nested_write"

      include CascadingDestroy
      include NestedWrite

      private

      # Call before destroying the parent record.
      # Handles all associations with a non-:ignore dependent option.
      #
      # @param parent_record [ActiveRecord::Base]
      # @return [Result]
      def handle_cascading_destroy(parent_record)
        cascading_destroy(parent_record)
      end
    end
  end
end
