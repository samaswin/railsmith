# frozen_string_literal: true

module Railsmith
  class BaseService
    module NestedWriter
      # Implements cascading destroy behaviors for declared associations.
      module CascadingDestroy
        private

        def cascading_destroy(parent_record)
          registry = self.class.association_registry
          return Result.success(value: parent_record) unless registry.any?

          registry.all.each do |definition|
            next if definition.dependent == :ignore

            result = cascade_dependent(definition, parent_record)
            return result if result.failure?
          end

          Result.success(value: parent_record)
        end

        def cascade_dependent(definition, parent_record)
          foreign_key = definition.inferred_foreign_key(model_class)

          case definition.dependent
          when :destroy  then cascade_destroy(definition, parent_record, foreign_key)
          when :nullify  then cascade_nullify(definition, parent_record, foreign_key)
          when :restrict then cascade_restrict(definition, parent_record, foreign_key)
          else                Result.success(value: nil)
          end
        end

        def cascade_destroy(definition, parent_record, foreign_key)
          each_associated_id(definition, parent_record, foreign_key) do |record_id|
            definition.service_class.call(action: :destroy, params: { id: record_id }, context: context)
          end
        end

        def cascade_nullify(definition, parent_record, foreign_key)
          each_associated_id(definition, parent_record, foreign_key) do |record_id|
            definition.service_class.call(
              action: :update,
              params: { id: record_id, attributes: { foreign_key => nil } },
              context: context
            )
          end
        end

        def cascade_restrict(definition, parent_record, foreign_key)
          child_model = definition.service_class.respond_to?(:model) ? definition.service_class.model : nil
          return Result.success(value: nil) unless child_model

          count = child_model.where(foreign_key => parent_record.id).count
          return Result.success(value: nil) if count.zero?

          Result.failure(
            error: Errors.validation_error(
              message: "Cannot delete record: #{count} #{definition.name} record(s) still exist",
              details: { association: definition.name, count: count }
            )
          )
        end

        def each_associated_id(definition, parent_record, foreign_key)
          child_model = definition.service_class.respond_to?(:model) ? definition.service_class.model : nil
          return Result.success(value: nil) unless child_model

          child_model.where(foreign_key => parent_record.id).pluck(:id).each do |record_id|
            result = yield(record_id)
            return result if result.failure?
          end

          Result.success(value: nil)
        end
      end
    end
  end
end
