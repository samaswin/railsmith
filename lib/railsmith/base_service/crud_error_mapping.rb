# frozen_string_literal: true

module Railsmith
  class BaseService
    # Maps common persistence exceptions to Railsmith error payloads.
    module CrudErrorMapping
      private

      def validation_error_for_record(record)
        details =
          if record.respond_to?(:errors) && record.errors.respond_to?(:to_hash)
            { errors: record.errors.to_hash(true) }
          else
            { errors: { base: ["Validation failed"] } }
          end

        Errors.validation_error(details:)
      end

      def map_exception_to_error(exception)
        mapped = map_active_record_exception(exception)
        return mapped unless mapped.nil?

        Errors.unexpected(details: { exception_class: exception.class.name, message: exception.message })
      end

      def map_active_record_exception(exception)
        return nil unless defined?(ActiveRecord)

        not_found_error(exception) ||
          record_invalid_error(exception) ||
          not_unique_error(exception) ||
          stale_object_error(exception)
      end

      def not_found_error(exception)
        return nil unless defined?(ActiveRecord::RecordNotFound)
        return nil unless exception.is_a?(ActiveRecord::RecordNotFound)

        Errors.not_found(message: "Record not found", details: { message: exception.message })
      end

      def record_invalid_error(exception)
        return nil unless defined?(ActiveRecord::RecordInvalid)
        return nil unless exception.is_a?(ActiveRecord::RecordInvalid)

        record = exception.record
        return nil if record.nil?

        validation_error_for_record(record)
      end

      def not_unique_error(exception)
        return nil unless defined?(ActiveRecord::RecordNotUnique)
        return nil unless exception.is_a?(ActiveRecord::RecordNotUnique)

        Errors.conflict(message: "Conflict", details: { message: exception.message })
      end

      def stale_object_error(exception)
        return nil unless defined?(ActiveRecord::StaleObjectError)
        return nil unless exception.is_a?(ActiveRecord::StaleObjectError)

        Errors.conflict(message: "Conflict", details: { message: exception.message })
      end

      def missing_model_class_result
        Result.failure(
          error: Errors.validation_error(
            message: "Model class not configured",
            details: { service: self.class.name }
          )
        )
      end
    end
  end
end
