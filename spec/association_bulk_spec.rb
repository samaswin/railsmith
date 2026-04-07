# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService bulk operations with associations" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :ab_orders, force: true do |t|
        t.string :name, null: false
        t.timestamps null: false
      end

      create_table :ab_items, force: true do |t|
        t.integer :ab_order_id
        t.string  :name, null: false
        t.timestamps null: false
      end
    end

    Object.const_set(:AbOrder, Class.new(ActiveRecord::Base) do
      self.table_name = "ab_orders"
      validates :name, presence: true
    end)
    Object.const_set(:AbItem, Class.new(ActiveRecord::Base) do
      self.table_name = "ab_items"
      validates :name, presence: true
    end)
  end

  after(:all) do
    %i[AbOrder AbItem].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
  end

  before do
    AbOrder.delete_all
    AbItem.delete_all
  end

  let(:ab_item_service) { Class.new(Railsmith::BaseService) { model AbItem } }

  def build_order_service(item_svc)
    Class.new(Railsmith::BaseService) do
      model AbOrder
      has_many :ab_items, service: item_svc
    end
  end

  # =========================================================================
  # 1. bulk_create with nested items (all_or_nothing mode)
  # =========================================================================

  describe "bulk_create with nested has_many (all_or_nothing)" do
    it "creates all parents and their nested items" do
      svc = build_order_service(ab_item_service)

      result = svc.call(
        action: :bulk_create,
        params: {
          items: [
            {
              attributes: { name: "Order A" },
              ab_items: [
                { attributes: { name: "Item A1" } },
                { attributes: { name: "Item A2" } }
              ]
            },
            {
              attributes: { name: "Order B" },
              ab_items: [
                { attributes: { name: "Item B1" } }
              ]
            }
          ]
        },
        context: {}
      )

      expect(result).to be_success
      expect(AbOrder.count).to eq(2)
      expect(AbItem.count).to eq(3)
    end

    it "injects parent FK into each nested item" do
      svc = build_order_service(ab_item_service)

      svc.call(
        action: :bulk_create,
        params: {
          items: [
            {
              attributes: { name: "Order FK" },
              ab_items: [{ attributes: { name: "Child" } }]
            }
          ]
        },
        context: {}
      )

      order = AbOrder.first
      item  = AbItem.first
      expect(item.ab_order_id).to eq(order.id)
    end

    it "rolls back everything when a nested item fails (all_or_nothing)" do
      svc = build_order_service(ab_item_service)

      result = svc.call(
        action: :bulk_create,
        params: {
          transaction_mode: :all_or_nothing,
          items: [
            {
              attributes: { name: "Good Order" },
              ab_items: [{ attributes: { name: "Good Item" } }]
            },
            {
              attributes: { name: "Bad Order" },
              ab_items: [{ attributes: { name: nil } }] # name required → fails
            }
          ]
        },
        context: {}
      )

      # all_or_nothing rolls back the DB but still returns a success Result
      # with the summary reflecting what happened — callers check all_succeeded.
      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(
        total: 2,
        success_count: 1,
        failure_count: 1,
        all_succeeded: false
      )
      expect(AbOrder.count).to eq(0)
      expect(AbItem.count).to eq(0)
    end
  end

  # =========================================================================
  # 2. bulk_create with nested items (best_effort mode)
  # =========================================================================

  describe "bulk_create with nested has_many (best_effort)" do
    it "creates successful parents and skips failing ones" do
      svc = build_order_service(ab_item_service)

      result = svc.call(
        action: :bulk_create,
        params: {
          transaction_mode: :best_effort,
          items: [
            {
              attributes: { name: "Good Order" },
              ab_items: [{ attributes: { name: "Good Item" } }]
            },
            {
              attributes: { name: "Bad Order" },
              ab_items: [{ attributes: { name: nil } }] # name required → fails
            }
          ]
        },
        context: {}
      )

      expect(result).to be_success
      summary = result.value.fetch(:summary)
      expect(summary).to include(total: 2, success_count: 1, failure_count: 1)
      expect(AbOrder.count).to eq(1)
      expect(AbOrder.first.name).to eq("Good Order")
    end
  end

  # =========================================================================
  # 3. bulk_create without nested params — creates parents only
  # =========================================================================

  describe "bulk_create without nested params" do
    it "creates parents normally when no nested key is present" do
      svc = build_order_service(ab_item_service)

      result = svc.call(
        action: :bulk_create,
        params: {
          items: [
            { attributes: { name: "Order X" } },
            { attributes: { name: "Order Y" } }
          ]
        },
        context: {}
      )

      expect(result).to be_success
      expect(AbOrder.count).to eq(2)
      expect(AbItem.count).to eq(0)
    end

    it "supports flat-format bulk items alongside a service with associations" do
      svc = build_order_service(ab_item_service)

      result = svc.call(
        action: :bulk_create,
        params: {
          items: [
            { name: "Flat A" },
            { name: "Flat B" }
          ]
        },
        context: {}
      )

      expect(result).to be_success
      expect(AbOrder.count).to eq(2)
    end
  end

  # =========================================================================
  # 4. Service without associations — bulk_create unaffected
  # =========================================================================

  describe "service without associations" do
    it "bulk_create works normally" do
      plain_svc = Class.new(Railsmith::BaseService) { model AbOrder }

      result = plain_svc.call(
        action: :bulk_create,
        params: {
          items: [{ name: "P1" }, { name: "P2" }]
        },
        context: {}
      )

      expect(result).to be_success
      expect(AbOrder.count).to eq(2)
    end
  end
end
