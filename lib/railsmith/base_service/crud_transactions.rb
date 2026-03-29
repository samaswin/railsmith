# frozen_string_literal: true

module Railsmith
  class BaseService
    # Transaction helpers for write-path actions.
    # @api private
    module CrudTransactions
      private

      def with_transaction(model_klass)
        result = nil
        transaction_wrapper(model_klass) do
          result = yield
          rollback_transaction if result.is_a?(Result) && result.failure?
        end
        result
      end

      def transaction_wrapper(model_klass, &)
        return model_klass.transaction(&) if model_klass.respond_to?(:transaction)
        return ActiveRecord::Base.transaction(&) if defined?(ActiveRecord::Base)

        yield
      end

      def rollback_transaction
        raise ActiveRecord::Rollback if defined?(ActiveRecord::Rollback)
      end
    end
  end
end
