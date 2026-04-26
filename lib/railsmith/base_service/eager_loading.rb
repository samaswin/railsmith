# frozen_string_literal: true

module Railsmith
  class BaseService
    # Adds a class-level `includes` DSL macro for declaring eager loads.
    #
    # Declared includes are applied automatically in `find_record` (via
    # `base_scope`) and in the default `list` action.
    #
    # Usage:
    #
    #   class OrderService < Railsmith::BaseService
    #     model Order
    #     domain :commerce
    #
    #     includes :line_items, :customer
    #     includes line_items: [:product, :variant]   # multiple calls are additive
    #   end
    #
    module EagerLoading
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class-level DSL macros for declaring eager loads on a service.
      module ClassMethods
        # Declare one or more eager loads. Multiple calls are additive.
        #
        # Accepts the same arguments as ActiveRecord's `includes`:
        #   includes :foo, :bar
        #   includes foo: :bar
        #   includes foo: [:bar, :baz]
        #
        # You can scope eager loads to specific actions:
        #   includes :readers, only: %i[find list]
        #   includes :audit_logs, except: %i[list]
        def includes(*args, **kwargs)
          only = kwargs.delete(:only)
          except = kwargs.delete(:except)
          validate_includes_scope!(only:, except:)

          args << kwargs unless kwargs.empty?

          @eager_loads ||= []
          @eager_loads.concat(args)

          add_eager_load_rule(args:, only:, except:)
        end

        # Returns the accumulated eager-load arguments for this class.
        def eager_loads
          @eager_loads || []
        end

        # Returns eager-load arguments that apply to the given action.
        #
        # @param action [Symbol, String, nil]
        # @return [Array]
        def eager_loads_for(action)
          rules = @eager_load_rules || []
          return eager_loads if rules.empty?

          normalized_action = action&.to_sym

          matching_rules = rules.select { |rule| eager_load_rule_applies?(rule, normalized_action) }
          matching_rules.flat_map { |rule| rule.fetch(:args) }
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@eager_loads, eager_loads.dup)
          subclass.instance_variable_set(:@eager_load_rules, eager_load_rules_dup)
        end

        private

        def validate_includes_scope!(only:, except:)
          return unless !only.nil? && !except.nil?

          raise ArgumentError, "`includes` accepts either `only:` or `except:`, not both"
        end

        def eager_load_rule_applies?(rule, normalized_action)
          only_actions = rule.fetch(:only)
          except_actions = rule.fetch(:except)

          return false if only_actions && !only_actions.include?(normalized_action)
          return false if except_actions&.include?(normalized_action)

          true
        end

        def add_eager_load_rule(args:, only:, except:)
          @eager_load_rules ||= []
          @eager_load_rules << {
            args: args,
            only: normalize_action_list(only),
            except: normalize_action_list(except)
          }
        end

        def normalize_action_list(value)
          return nil if value.nil?

          Array(value).map(&:to_sym).uniq
        end

        def eager_load_rules_dup
          rules = @eager_load_rules || []
          rules.map do |rule|
            {
              args: rule.fetch(:args).dup,
              only: rule.fetch(:only)&.dup,
              except: rule.fetch(:except)&.dup
            }
          end
        end
      end

      private

      # Returns a scoped relation with eager loads applied if any are declared.
      # Falls back to the bare model class when no eager loads are configured.
      #
      # @param model_klass [Class]  the ActiveRecord model class
      # @return [ActiveRecord::Relation, Class]
      def base_scope(model_klass)
        loads = self.class.eager_loads_for(@current_action)
        return model_klass if loads.empty?

        model_klass.includes(*loads)
      end
    end
  end
end
