# frozen_string_literal: true

module Railsmith
  class BaseService
    # Model resolution helpers for CRUD defaults.
    # @api private
    module CrudModelResolution
      private

      def model_class
        explicit = self.class.model
        return explicit unless explicit.nil?

        infer_model_class
      end

      def infer_model_class
        return nil unless self.class.name

        name = self.class.name.to_s
        return nil unless name.end_with?("Service")

        safe_constantize(name.delete_suffix("Service"))
      end

      def safe_constantize(constant_name)
        return constant_name.constantize if constant_name.respond_to?(:constantize)
        return nil unless defined?(ActiveSupport::Inflector)

        ActiveSupport::Inflector.safe_constantize(constant_name.to_s)
      rescue NameError
        nil
      end
    end
  end
end
