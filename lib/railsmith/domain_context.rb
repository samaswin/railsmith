# frozen_string_literal: true

require_relative "context"

module Railsmith
  # @deprecated Use Railsmith::Context instead.
  # Kept for one major version to allow migration. Will be removed in the next major release.
  class DomainContext < Context
    # Overrides Context.new to:
    #   - emit a class-level deprecation warning
    #   - map the old +meta:+ keyword to top-level extras
    def self.new(current_domain: nil, meta: {}, **extras)
      warn "[DEPRECATION] Railsmith::DomainContext is deprecated; use Railsmith::Context instead."
      merged_extras = (meta || {}).merge(extras)
      super(domain: current_domain, **merged_extras)
    end

    # Backward-compatible reader. Returns the stored extras (the former :meta hash).
    def meta
      @extras
    end
  end
end
