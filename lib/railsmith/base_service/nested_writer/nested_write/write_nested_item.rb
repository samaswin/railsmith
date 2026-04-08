# frozen_string_literal: true

module Railsmith
  class BaseService
    module NestedWriter
      module NestedWrite
        # Writes a single nested item (create/update/destroy).
        module WriteNestedItem
          private

          def truthy_destroy_flag?(flag)
            [true, "true", "1", 1].include?(flag)
          end

          def extract_attributes(item_params)
            attrs = item_params[:attributes] || item_params["attributes"] || {}
            attrs.is_a?(Hash) ? attrs : {}
          end

          def call_nested_service(definition, action, params:)
            definition.service_class.call(action: action, params: params, context: context)
          end

          def write_nested_item(definition, item_params, foreign_key, foreign_value, _mode)
            return Result.success(value: nil) unless item_params.is_a?(Hash)

            item_id = item_params[:id] || item_params["id"]
            destroy_flag = item_params[:_destroy] || item_params["_destroy"]

            if item_id && truthy_destroy_flag?(destroy_flag)
              destroy_nested(definition, item_id)
            elsif item_id
              update_nested(definition, item_id, item_params, foreign_key, foreign_value)
            else
              create_nested(definition, item_params, foreign_key, foreign_value)
            end
          end

          def destroy_nested(definition, item_id)
            call_nested_service(definition, :destroy, params: { id: item_id })
          end

          def update_nested(definition, item_id, item_params, foreign_key, foreign_value)
            attrs = nested_item_attributes(item_params, foreign_key, foreign_value)
            call_nested_service(definition, :update, params: { id: item_id, attributes: attrs })
          end

          def create_nested(definition, item_params, foreign_key, foreign_value)
            attrs = nested_item_attributes(item_params, foreign_key, foreign_value)
            call_nested_service(definition, :create, params: { attributes: attrs })
          end

          def nested_item_attributes(item_params, foreign_key, foreign_value)
            extract_attributes(item_params).merge(foreign_key => foreign_value)
          end
        end
      end
    end
  end
end
