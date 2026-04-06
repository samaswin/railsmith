# frozen_string_literal: true

module Railsmith
  class BaseService
    # Value object representing a single declared input on a service.
    class InputDefinition
      # Sentinel distinguishing "no default set" from "default: nil".
      # Not private — referenced as the keyword-arg default in InputDsl#input.
      UNSET = Object.new.freeze

      attr_reader :name, :type, :required, :default, :in_values, :transform

      # @param name     [Symbol, String]  input key
      # @param type     [Class, Symbol]   expected type (e.g. String, Integer, :boolean)
      # @param required [Boolean]         whether absence is a validation error
      # @param default  [Object, Proc]    static value or lambda called to produce default
      # @param in       [Array, nil]      allowed values whitelist
      # @param transform [Proc, nil]      optional post-coercion transformation
      def initialize(name, type, required: false, default: UNSET, in: nil, transform: nil)
        @name      = name.to_sym
        @type      = type
        @required  = required
        @default   = default
        @in_values = binding.local_variable_get(:in)
        @transform = transform
        freeze
      end

      def has_default?
        !@default.equal?(UNSET)
      end

      def resolve_default
        default.respond_to?(:call) ? default.call : default
      end
    end
  end
end
