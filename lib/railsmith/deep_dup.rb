# frozen_string_literal: true

# Railsmith — lightweight service/operation framework for Rails.
module Railsmith
  module_function

  # Deep-duplicates Hash/Array trees for defensive copies (params/context).
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
