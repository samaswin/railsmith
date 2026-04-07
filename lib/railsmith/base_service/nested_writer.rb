# frozen_string_literal: true

module Railsmith
  class BaseService
    # Handles nested association writes within service actions.
    #
    # All nested operations delegate to the associated service class, running
    # within the caller's open transaction so any failure triggers a full
    # rollback of parent + nested writes.
    #
    # Nested create flow (has_many / has_one):
    #   1. Parent record is already persisted
    #   2. For each declared association with nested params in the call's params:
    #      a. Inject parent FK into each item's attributes
    #      b. Delegate to associated service (create / update / destroy)
    #   3. Return success with parent record, or first failure (caller rolls back)
    #
    # Nested update semantics per item:
    #   - has id + attributes    → :update via associated service
    #   - has attributes only    → :create via associated service (FK injected)
    #   - has id + _destroy: true → :destroy via associated service
    #
    # Cascading destroy:
    #   dependent: :destroy  → calls associated service destroy for each child
    #   dependent: :nullify  → calls associated service update with FK set to nil
    #   dependent: :restrict → returns failure if any children exist
    #   dependent: :ignore   → does nothing (rely on DB constraints)
    #
    module NestedWriter
      private

      # Call after successfully persisting a parent record during :create.
      # Reads nested association params from the service's own @params.
      #
      # @param parent_record [ActiveRecord::Base]
      # @return [Result]
      def write_nested_after_create(parent_record)
        write_nested(parent_record, @params, :create)
      end

      # Call after successfully persisting a parent record during :update.
      # Reads nested association params from the service's own @params.
      #
      # @param parent_record [ActiveRecord::Base]
      # @return [Result]
      def write_nested_after_update(parent_record)
        write_nested(parent_record, @params, :update)
      end

      # For bulk operations where each item has its own nested params.
      #
      # @param parent_record [ActiveRecord::Base]
      # @param item_params   [Hash]  the individual bulk item hash
      # @param mode          [Symbol] :create or :update
      # @return [Result]
      def write_nested_for_item(parent_record, item_params, mode)
        write_nested(parent_record, item_params, mode)
      end

      # Call before destroying the parent record.
      # Handles all associations with a non-:ignore dependent option.
      #
      # @param parent_record [ActiveRecord::Base]
      # @return [Result]
      def handle_cascading_destroy(parent_record)
        registry = self.class.association_registry
        return Result.success(value: parent_record) unless registry.any?

        registry.all.each do |defn|
          next if defn.dependent == :ignore

          result = cascade_dependent(defn, parent_record)
          return result if result.failure?
        end

        Result.success(value: parent_record)
      end

      # -----------------------------------------------------------------------
      # Private implementation
      # -----------------------------------------------------------------------

      def write_nested(parent_record, source_params, mode)
        registry = self.class.association_registry
        return Result.success(value: parent_record) unless registry.any?

        nested_meta = {}

        registry.all.each do |defn|
          # belongs_to FK is on this record — not a nested write target
          next if defn.kind == :belongs_to
          next unless source_params.is_a?(Hash) && source_params.key?(defn.name)

          nested_params = source_params[defn.name]
          fk_key        = defn.inferred_foreign_key(model_class)

          result = dispatch_nested(defn, nested_params, fk_key, parent_record.id, mode)
          return result if result.failure?

          nested_meta[defn.name] = result.meta if result.meta
        end

        meta = nested_meta.empty? ? nil : { nested: nested_meta }
        Result.success(value: parent_record, meta: meta)
      end

      def dispatch_nested(defn, nested_params, fk_key, fk_value, mode)
        case defn.kind
        when :has_many then write_has_many(defn, nested_params, fk_key, fk_value, mode)
        when :has_one  then write_has_one(defn, nested_params, fk_key, fk_value, mode)
        else                Result.success(value: nil)
        end
      end

      def write_has_many(defn, nested_params, fk_key, fk_value, mode)
        return Result.success(value: []) unless nested_params.is_a?(Array)

        success_values = []

        nested_params.each do |item_params|
          result = write_nested_item(defn, item_params, fk_key, fk_value, mode)
          return result if result.failure?

          success_values << result.value
        end

        total = nested_params.size
        Result.success(
          value: success_values,
          meta:  { total: total, success_count: total, failure_count: 0 }
        )
      end

      def write_has_one(defn, nested_params, fk_key, fk_value, mode)
        return Result.success(value: nil) unless nested_params.is_a?(Hash)

        write_nested_item(defn, nested_params, fk_key, fk_value, mode)
      end

      def write_nested_item(defn, item_params, fk_key, fk_value, _mode)
        return Result.success(value: nil) unless item_params.is_a?(Hash)

        item_id      = item_params[:id]      || item_params["id"]
        destroy_flag = item_params[:_destroy] || item_params["_destroy"]

        if item_id && truthy_destroy_flag?(destroy_flag)
          defn.service_class.call(
            action:  :destroy,
            params:  { id: item_id },
            context: context
          )
        elsif item_id
          attrs = extract_attributes(item_params).merge(fk_key => fk_value)
          defn.service_class.call(
            action:  :update,
            params:  { id: item_id, attributes: attrs },
            context: context
          )
        else
          attrs = extract_attributes(item_params).merge(fk_key => fk_value)
          defn.service_class.call(
            action:  :create,
            params:  { attributes: attrs },
            context: context
          )
        end
      end

      def truthy_destroy_flag?(flag)
        [true, "true", "1", 1].include?(flag)
      end

      def extract_attributes(item_params)
        attrs = item_params[:attributes] || item_params["attributes"] || {}
        attrs.is_a?(Hash) ? attrs : {}
      end

      # -----------------------------------------------------------------------
      # Cascading destroy helpers
      # -----------------------------------------------------------------------

      def cascade_dependent(defn, parent_record)
        fk_key = defn.inferred_foreign_key(model_class)

        case defn.dependent
        when :destroy  then cascade_destroy(defn, parent_record, fk_key)
        when :nullify  then cascade_nullify(defn, parent_record, fk_key)
        when :restrict then cascade_restrict(defn, parent_record, fk_key)
        else                Result.success(value: nil)
        end
      end

      def cascade_destroy(defn, parent_record, fk_key)
        each_associated_id(defn, parent_record, fk_key) do |id|
          defn.service_class.call(action: :destroy, params: { id: id }, context: context)
        end
      end

      def cascade_nullify(defn, parent_record, fk_key)
        each_associated_id(defn, parent_record, fk_key) do |id|
          defn.service_class.call(
            action:  :update,
            params:  { id: id, attributes: { fk_key => nil } },
            context: context
          )
        end
      end

      def cascade_restrict(defn, parent_record, fk_key)
        child_model = defn.service_class.respond_to?(:model) ? defn.service_class.model : nil
        return Result.success(value: nil) unless child_model

        count = child_model.where(fk_key => parent_record.id).count
        return Result.success(value: nil) if count.zero?

        Result.failure(
          error: Errors.validation_error(
            message: "Cannot delete record: #{count} #{defn.name} record(s) still exist",
            details: { association: defn.name, count: count }
          )
        )
      end

      # Iterates each child record's id, calling the block and returning the
      # first failure result, or success if all passed.
      def each_associated_id(defn, parent_record, fk_key)
        child_model = defn.service_class.respond_to?(:model) ? defn.service_class.model : nil
        return Result.success(value: nil) unless child_model

        child_model.where(fk_key => parent_record.id).pluck(:id).each do |id|
          result = yield(id)
          return result if result.failure?
        end

        Result.success(value: nil)
      end
    end
  end
end
