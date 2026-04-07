# frozen_string_literal: true

module Railsmith
  class BaseService
    module NestedWriter
      # Implements nested association writes for declared associations.
      module NestedWrite
        require_relative "nested_write/write_nested"
        require_relative "nested_write/write_nested_item"

        include WriteNested
        include WriteNestedItem
      end
    end
  end
end
