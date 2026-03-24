# frozen_string_literal: true

module Railsmith
  # Stores global settings used by gem components.
  class Configuration
    attr_accessor :warn_on_cross_domain_calls, :strict_mode, :serializer_adapter

    def initialize
      @warn_on_cross_domain_calls = true
      @strict_mode = false
      @serializer_adapter = :auto
    end
  end
end
