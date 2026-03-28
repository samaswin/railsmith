# frozen_string_literal: true

module Railsmith
  class BaseService
    # Deep-duplication helpers for params/context immutability.
    module DupHelpers
      private

      def deep_dup(value)
        Railsmith.deep_dup(value)
      end
    end
  end
end
