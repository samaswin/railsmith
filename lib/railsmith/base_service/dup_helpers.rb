# frozen_string_literal: true

module Railsmith
  class BaseService
    # Deep-duplication helpers for params/context immutability.
    module DupHelpers
      private

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), memo| memo[key] = deep_dup(item) }
        when Array
          value.map { |item| deep_dup(item) }
        else
          value.dup
        end
      rescue TypeError
        value
      end
    end
  end
end
