# frozen_string_literal: true

module Railsmith
  class BaseService
    # Parses and normalizes bulk action params.
    module BulkParams
      DEFAULT_BULK_LIMIT = 1000
      DEFAULT_BATCH_SIZE = 100
      TRANSACTION_MODE_ALL_OR_NOTHING = :all_or_nothing
      TRANSACTION_MODE_BEST_EFFORT = :best_effort

      private

      def bulk_items
        return [] unless params.is_a?(Hash)

        items = params[:items]
        return items if items.is_a?(Array)

        []
      end

      def bulk_limit
        return DEFAULT_BULK_LIMIT unless params.is_a?(Hash)

        configured = params[:limit]
        return DEFAULT_BULK_LIMIT unless configured.is_a?(Integer)
        return DEFAULT_BULK_LIMIT if configured <= 0

        configured
      end

      def bulk_batch_size
        return DEFAULT_BATCH_SIZE unless params.is_a?(Hash)

        configured = params[:batch_size]
        return DEFAULT_BATCH_SIZE unless configured.is_a?(Integer)
        return DEFAULT_BATCH_SIZE if configured <= 0

        configured
      end

      def bulk_transaction_mode
        return TRANSACTION_MODE_ALL_OR_NOTHING unless params.is_a?(Hash)

        mode = params[:transaction_mode]
        mode = mode.to_sym if mode.respond_to?(:to_sym)

        return mode if [TRANSACTION_MODE_ALL_OR_NOTHING, TRANSACTION_MODE_BEST_EFFORT].include?(mode)

        TRANSACTION_MODE_ALL_OR_NOTHING
      end
    end
  end
end
