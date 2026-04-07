# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService Eager Loading" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :el_products, force: true do |t|
        t.string :name, null: false
        t.timestamps null: false
      end

      create_table :el_tags, force: true do |t|
        t.integer :el_product_id
        t.string  :label
        t.timestamps null: false
      end
    end

    el_product_class = Class.new(ActiveRecord::Base) do
      self.table_name = "el_products"
      has_many :el_tags, foreign_key: :el_product_id
    end

    el_tag_class = Class.new(ActiveRecord::Base) do
      self.table_name = "el_tags"
      belongs_to :el_product, foreign_key: :el_product_id
    end

    Object.const_set(:ElProduct, el_product_class)
    Object.const_set(:ElTag,     el_tag_class)
  end

  after(:all) do
    Object.send(:remove_const, :ElProduct) if Object.const_defined?(:ElProduct)
    Object.send(:remove_const, :ElTag)     if Object.const_defined?(:ElTag)
  end

  before do
    ElProduct.delete_all
    ElTag.delete_all
  end

  # =========================================================================
  # 1. includes macro — class-level API
  # =========================================================================

  describe "includes macro" do
    it "stores a single includes argument" do
      svc = Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags
      end

      expect(svc.eager_loads).to eq([:el_tags])
    end

    it "stores multiple arguments from one call" do
      svc = Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags, :other
      end

      expect(svc.eager_loads).to eq(%i[el_tags other])
    end

    it "accumulates multiple includes calls" do
      svc = Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags
        includes :other
      end

      expect(svc.eager_loads).to contain_exactly(:el_tags, :other)
    end

    it "accepts hash-style nested includes" do
      svc = Class.new(Railsmith::BaseService) do
        model ElProduct
        includes el_tags: :another
      end

      expect(svc.eager_loads).to eq([{ el_tags: :another }])
    end

    it "defaults to an empty array when not declared" do
      svc = Class.new(Railsmith::BaseService) { model ElProduct }
      expect(svc.eager_loads).to eq([])
    end
  end

  # =========================================================================
  # 2. Inheritance
  # =========================================================================

  describe "inheritance" do
    let(:parent) do
      Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags
      end
    end

    it "subclass inherits parent eager loads" do
      child = Class.new(parent)
      expect(child.eager_loads).to include(:el_tags)
    end

    it "subclass can add without modifying parent" do
      child = Class.new(parent) { includes :extra }

      expect(child.eager_loads).to include(:el_tags, :extra)
      expect(parent.eager_loads).not_to include(:extra)
    end
  end

  # =========================================================================
  # 3. list — applies eager loads
  # =========================================================================

  describe "list with eager loading" do
    let(:service_with_includes) do
      Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags
      end
    end

    let(:service_without_includes) do
      Class.new(Railsmith::BaseService) { model ElProduct }
    end

    before do
      product = ElProduct.create!(name: "Widget")
      ElTag.create!(el_product_id: product.id, label: "sale")
    end

    it "returns success with all records" do
      result = service_with_includes.call(action: :list, params: {}, context: {})
      expect(result).to be_success
      expect(result.value.to_a.size).to eq(1)
    end

    it "preloads associations when includes is declared" do
      result = service_with_includes.call(action: :list, params: {}, context: {})
      records = result.value.to_a
      expect(records.first.association(:el_tags).loaded?).to be true
    end

    it "does not preload associations when includes is not declared" do
      result = service_without_includes.call(action: :list, params: {}, context: {})
      records = result.value.to_a
      expect(records.first.association(:el_tags).loaded?).to be false
    end
  end

  # =========================================================================
  # 4. find — applies eager loads via base_scope
  # =========================================================================

  describe "find with eager loading" do
    let(:service_with_includes) do
      Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags
      end
    end

    it "returns the correct record" do
      product = ElProduct.create!(name: "Gadget")
      ElTag.create!(el_product_id: product.id, label: "new")

      result = service_with_includes.call(
        action: :find, params: { id: product.id }, context: {}
      )

      expect(result).to be_success
      expect(result.value.id).to eq(product.id)
    end

    it "returns not_found for missing record" do
      result = service_with_includes.call(
        action: :find, params: { id: 999_999 }, context: {}
      )

      expect(result).to be_failure
      expect(result.code).to eq("not_found")
    end
  end

  # =========================================================================
  # 5. Custom action can override list to bypass eager loads
  # =========================================================================

  describe "custom list override" do
    it "custom list method replaces default eager-loading behavior" do
      svc = Class.new(Railsmith::BaseService) do
        model ElProduct
        includes :el_tags

        def list
          Railsmith::Result.success(value: ElProduct.all)
        end
      end

      ElProduct.create!(name: "Plain")
      result = svc.call(action: :list, params: {}, context: {})
      records = result.value.to_a

      expect(result).to be_success
      expect(records.first.association(:el_tags).loaded?).to be false
    end
  end
end
