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
      # @param options [Hash]            supported keys: :required, :default, :in, :transform
      def initialize(name, type, **options)
        @name      = name.to_sym
        @type      = type
        @required  = options.fetch(:required, false)
        @default   = options.fetch(:default, UNSET)
        @in_values = options[:in]
        @transform = options[:transform]
        freeze
      end

      def default?
        !@default.equal?(UNSET)
      end

      def resolve_default
        default.respond_to?(:call) ? default.call : default
      end
    end
  end
end
