# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService input DSL" do
  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  # Build a service class with no model (custom-action style inputs)
  def custom_service(&block)
    Class.new(Railsmith::BaseService) do
      class_eval(&block) if block
    end
  end

  # Build a service class backed by a model (CRUD-style inputs on attributes)
  def crud_service(model_klass, &block)
    Class.new(Railsmith::BaseService) do
      model model_klass
      class_eval(&block) if block
    end
  end

  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :items, force: true do |t|
        t.string  :name
        t.integer :quantity
        t.timestamps null: false
      end
    end

    item_class = Class.new(ActiveRecord::Base) do
      self.table_name = "items"
    end

    Object.const_set(:Item, item_class)
  end

  after(:all) do
    Object.send(:remove_const, :Item) if Object.const_defined?(:Item)
  end

  # =========================================================================
  # 1. Declaration & registry
  # =========================================================================

  describe "input declaration" do
    it "registers inputs on the service class" do
      svc = custom_service do
        input :email, String, required: true
        input :age,   Integer
      end

      expect(svc.input_registry.all.map(&:name)).to eq(%i[email age])
    end

    it "stores type, required, and default" do
      svc = custom_service do
        input :role, String, required: false, default: "member"
      end

      defn = svc.input_registry[:role]
      expect(defn.type).to eq(String)
      expect(defn.required).to be false
      expect(defn.resolve_default).to eq("member")
    end

    it "stores lambda defaults without calling them at declaration time" do
      counter = 0
      svc = custom_service do
        input :tags, Array, default: -> { counter += 1; [] }
      end

      defn = svc.input_registry[:tags]
      expect(counter).to eq(0)
      defn.resolve_default
      expect(counter).to eq(1)
    end

    it "stores allowed-values constraint" do
      svc = custom_service do
        input :status, String, in: %w[active inactive]
      end

      expect(svc.input_registry[:status].in_values).to eq(%w[active inactive])
    end

    it "stores transform proc" do
      upcaser = ->(v) { v.upcase }
      svc = custom_service do
        input :code, String, transform: upcaser
      end

      expect(svc.input_registry[:code].transform).to eq(upcaser)
    end
  end

  # =========================================================================
  # 2. Inheritance
  # =========================================================================

  describe "inheritance" do
    let(:parent) do
      custom_service do
        input :name, String, required: true
        input :role, String, default: "member"
      end
    end

    it "subclass inherits parent inputs" do
      child = Class.new(parent)
      expect(child.input_registry[:name]).not_to be_nil
      expect(child.input_registry[:role]).not_to be_nil
    end

    it "subclass can add its own inputs without modifying parent" do
      child = Class.new(parent) do
        input :extra, Integer
      end

      expect(child.input_registry[:extra]).not_to be_nil
      expect(parent.input_registry[:extra]).to be_nil
    end

    it "subclass can override a parent input" do
      child = Class.new(parent) do
        input :role, String, default: "admin"
      end

      expect(child.input_registry[:role].resolve_default).to eq("admin")
      expect(parent.input_registry[:role].resolve_default).to eq("member")
    end
  end

  # =========================================================================
  # 3. Custom-action services (inputs on raw params)
  # =========================================================================

  describe "custom-action service" do
    let(:svc) do
      custom_service do
        input :email, String, required: true
        input :age,   Integer, default: nil

        def greet
          "hello #{params[:email]}"
        end
      end
    end

    it "resolves inputs and makes them available via params" do
      result = svc.call(action: :greet, params: { email: "a@b.com", age: "30" }, context: {})
      expect(result).to be_success
      expect(result.value).to eq("hello a@b.com")
    end

    it "returns validation_error when a required input is missing" do
      result = svc.call(action: :greet, params: {}, context: {})
      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.details[:errors]).to have_key(:email)
    end

    it "coerces string to integer" do
      svc2 = custom_service do
        input :count, Integer

        def total
          params[:count]
        end
      end

      result = svc2.call(action: :total, params: { count: "42" }, context: {})
      expect(result).to be_success
      expect(result.value).to eq(42)
    end

    it "applies default for missing optional input" do
      svc2 = custom_service do
        input :limit, Integer, default: 10

        def run
          params[:limit]
        end
      end

      result = svc2.call(action: :run, params: {}, context: {})
      expect(result).to be_success
      expect(result.value).to eq(10)
    end

    it "filters undeclared params by default" do
      svc2 = custom_service do
        input :name, String

        def run
          params
        end
      end

      result = svc2.call(action: :run, params: { name: "Alice", secret: "x" }, context: {})
      expect(result).to be_success
      expect(result.value).not_to have_key(:secret)
    end

    it "passes through undeclared params when filter_inputs false" do
      svc2 = custom_service do
        input :name, String
        filter_inputs false

        def run
          params
        end
      end

      result = svc2.call(action: :run, params: { name: "Alice", extra: "y" }, context: {})
      expect(result).to be_success
      expect(result.value).to have_key(:extra)
    end

    it "enforces in: constraint" do
      svc2 = custom_service do
        input :role, String, in: %w[admin member], default: "member"

        def run
          params[:role]
        end
      end

      result = svc2.call(action: :run, params: { role: "superuser" }, context: {})
      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.details[:errors]).to have_key(:role)
    end

    it "applies transform after coercion" do
      svc2 = custom_service do
        input :code, String, transform: ->(v) { v.upcase }

        def run
          params[:code]
        end
      end

      result = svc2.call(action: :run, params: { code: "abc" }, context: {})
      expect(result).to be_success
      expect(result.value).to eq("ABC")
    end
  end

  # =========================================================================
  # 4. CRUD service (inputs on params[:attributes])
  # =========================================================================

  describe "CRUD service with input DSL" do
    let(:svc) do
      crud_service(Item) do
        input :name,     String,  required: true
        input :quantity, Integer, default: 1
      end
    end

    it "creates a record when inputs are valid" do
      result = svc.call(
        action: :create,
        params: { attributes: { name: "Widget", quantity: "5" } },
        context: {}
      )

      expect(result).to be_success
      expect(result.value.name).to eq("Widget")
      expect(result.value.quantity).to eq(5)
    end

    it "returns validation_error when required input is missing" do
      result = svc.call(
        action: :create,
        params: { attributes: { quantity: 2 } },
        context: {}
      )

      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.details[:errors]).to have_key(:name)
    end

    it "applies default for omitted optional input" do
      result = svc.call(
        action: :create,
        params: { attributes: { name: "Gadget" } },
        context: {}
      )

      expect(result).to be_success
      expect(result.value.quantity).to eq(1)
    end

    it "filters undeclared attributes" do
      result = svc.call(
        action: :create,
        params: { attributes: { name: "X", quantity: 1, injected: "evil" } },
        context: {}
      )

      # Record is created without the injected key (Item doesn't have that column,
      # so the real test is that no error is raised and the record is saved fine)
      expect(result).to be_success
    end
  end

  # =========================================================================
  # 5. Backward compatibility — no inputs declared
  # =========================================================================

  describe "backward compatibility" do
    it "works identically to v1.1.0 when no inputs are declared" do
      svc = crud_service(Item)

      result = svc.call(
        action: :create,
        params: { attributes: { name: "Legacy" } },
        context: {}
      )

      expect(result).to be_success
      expect(result.value.name).to eq("Legacy")
    end

    it "does not affect existing validate() when no input DSL used" do
      svc = custom_service do
        def run
          result = validate(params, required_keys: [:token])
          return result if result.failure?

          Result.success(value: "ok")
        end
      end

      # Suppress deprecation warning for this backward-compat test
      expect { svc.call(action: :run, params: {}, context: {}) }.to output(/DEPRECATION/).to_stderr
    end
  end

  # =========================================================================
  # 6. filter_inputs class-level flag inheritance
  # =========================================================================

  describe "filter_inputs flag" do
    it "defaults to true" do
      svc = custom_service { input :x, String }
      expect(svc.filter_inputs).to be true
    end

    it "can be disabled" do
      svc = custom_service do
        input :x, String
        filter_inputs false
      end

      expect(svc.filter_inputs).to be false
    end

    it "is inherited by subclasses" do
      parent = custom_service do
        input :x, String
        filter_inputs false
      end
      child = Class.new(parent)
      expect(child.filter_inputs).to be false
    end
  end
end
