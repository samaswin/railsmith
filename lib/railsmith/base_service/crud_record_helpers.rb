# frozen_string_literal: true

module Railsmith
  class BaseService
    # Record building and lookup helpers for CRUD defaults.
    # @api private
    module CrudRecordHelpers
      private

      def attributes_params
        return params.fetch(:attributes) if params.is_a?(Hash) && params[:attributes].is_a?(Hash)
        return params if params.is_a?(Hash)

        {}
      end

      def sanitize_attributes(attributes)
        attributes
      end

      def record_id
        return params[:id] if params.is_a?(Hash) && params.key?(:id)

        nil
      end

      def find_record(model_klass, id)
        return missing_id_result if id.nil?

        record = model_klass.find_by(id:)
        return Result.success(value: record) unless record.nil?

        not_found_result(model_klass, id)
      rescue StandardError => e
        Result.failure(error: map_exception_to_error(e))
      end

      def build_record(model_klass, attributes)
        model_klass.new(attributes)
      end

      def assign_attributes(record, attributes)
        record.assign_attributes(attributes)
      end

      def missing_id_result
        Result.failure(error: Errors.validation_error(details: { missing: ["id"] }))
      end

      def not_found_result(model_klass, id)
        Result.failure(
          error: Errors.not_found(
            message: "Record not found",
            details: { model: model_klass.name, id: }
          )
        )
      end
    end
  end
end
