# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService cascading destroy" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :cd_orders, force: true do |t|
        t.string :name
        t.timestamps null: false
      end

      # cd_order_id is nullable to support :nullify cascade
      create_table :cd_items, force: true do |t|
        t.integer :cd_order_id
        t.string  :name
        t.timestamps null: false
      end

      create_table :cd_notes, force: true do |t|
        t.integer :cd_order_id
        t.string  :content
        t.timestamps null: false
      end
    end

    Object.const_set(:CdOrder, Class.new(ActiveRecord::Base) { self.table_name = "cd_orders" })
    Object.const_set(:CdItem,  Class.new(ActiveRecord::Base) { self.table_name = "cd_items" })
    Object.const_set(:CdNote,  Class.new(ActiveRecord::Base) { self.table_name = "cd_notes" })
  end

  after(:all) do
    %i[CdOrder CdItem CdNote].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
  end

  before do
    CdOrder.delete_all
    CdItem.delete_all
    CdNote.delete_all
  end

  let(:cd_item_service) { Class.new(Railsmith::BaseService) { model CdItem } }
  let(:cd_note_service) { Class.new(Railsmith::BaseService) { model CdNote } }

  def order_service_with(dependent:)
    item_svc = cd_item_service
    Class.new(Railsmith::BaseService) do
      model CdOrder
      has_many :cd_items, service: item_svc, dependent: dependent
    end
  end

  def create_order_with_items(count: 2)
    order = CdOrder.create!(name: "Test Order")
    count.times { |i| CdItem.create!(cd_order_id: order.id, name: "Item #{i}") }
    order
  end

  # =========================================================================
  # 1. dependent: :destroy
  # =========================================================================

  describe "dependent: :destroy" do
    it "destroys all child records before destroying the parent" do
      svc   = order_service_with(dependent: :destroy)
      order = create_order_with_items(count: 3)

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_success
      expect(CdOrder.find_by(id: order.id)).to be_nil
      expect(CdItem.where(cd_order_id: order.id).count).to eq(0)
    end

    it "succeeds when parent has no children" do
      svc   = order_service_with(dependent: :destroy)
      order = CdOrder.create!(name: "Empty")

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_success
      expect(CdOrder.find_by(id: order.id)).to be_nil
    end
  end

  # =========================================================================
  # 2. dependent: :nullify
  # =========================================================================

  describe "dependent: :nullify" do
    it "nullifies FK on child records and then destroys the parent" do
      svc   = order_service_with(dependent: :nullify)
      order = create_order_with_items(count: 2)
      item_ids = CdItem.where(cd_order_id: order.id).pluck(:id)

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_success
      expect(CdOrder.find_by(id: order.id)).to be_nil

      # Child records still exist, FK nullified
      expect(CdItem.where(id: item_ids).count).to eq(2)
      CdItem.where(id: item_ids).each do |item|
        expect(item.cd_order_id).to be_nil
      end
    end
  end

  # =========================================================================
  # 3. dependent: :restrict
  # =========================================================================

  describe "dependent: :restrict" do
    it "returns failure when children exist" do
      svc   = order_service_with(dependent: :restrict)
      order = create_order_with_items(count: 1)

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.details[:association]).to eq(:cd_items)
      expect(result.error.details[:count]).to eq(1)
    end

    it "does not destroy the parent when restriction fails" do
      svc   = order_service_with(dependent: :restrict)
      order = create_order_with_items(count: 1)

      svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(CdOrder.find_by(id: order.id)).not_to be_nil
    end

    it "allows destroy when no children exist" do
      svc   = order_service_with(dependent: :restrict)
      order = CdOrder.create!(name: "Childless")

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_success
      expect(CdOrder.find_by(id: order.id)).to be_nil
    end
  end

  # =========================================================================
  # 4. dependent: :ignore (default)
  # =========================================================================

  describe "dependent: :ignore" do
    it "destroys parent without touching child records" do
      svc   = order_service_with(dependent: :ignore)
      order = create_order_with_items(count: 2)

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_success
      expect(CdOrder.find_by(id: order.id)).to be_nil
      # Children survive with FK intact (dangling reference — DB-level concern)
      expect(CdItem.where(cd_order_id: order.id).count).to eq(2)
    end
  end

  # =========================================================================
  # 5. Multiple associations with mixed dependent options
  # =========================================================================

  describe "multiple associations" do
    it "processes each association's dependent option" do
      item_svc = cd_item_service
      note_svc = cd_note_service

      svc = Class.new(Railsmith::BaseService) do
        model CdOrder
        has_many :cd_items, service: item_svc, dependent: :destroy
        has_many :cd_notes, service: note_svc, dependent: :ignore
      end

      order = CdOrder.create!(name: "Mixed")
      CdItem.create!(cd_order_id: order.id, name: "I1")
      CdNote.create!(cd_order_id: order.id, content: "N1")

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_success
      expect(CdItem.where(cd_order_id: order.id).count).to eq(0)
      expect(CdNote.where(cd_order_id: order.id).count).to eq(1)
    end
  end

  # =========================================================================
  # 6. Transaction integrity — failed cascade aborts the destroy
  # =========================================================================

  describe "transaction integrity" do
    it "aborts parent destroy when a cascade step fails" do
      failing_item_svc = Class.new(Railsmith::BaseService) do
        model CdItem

        def destroy
          Railsmith::Result.failure(
            error: Railsmith::Errors.unexpected(message: "Cannot destroy item")
          )
        end
      end

      svc = Class.new(Railsmith::BaseService) do
        model CdOrder
        has_many :cd_items, service: failing_item_svc, dependent: :destroy
      end

      order = CdOrder.create!(name: "Should survive")
      CdItem.create!(cd_order_id: order.id, name: "Stubborn item")

      result = svc.call(action: :destroy, params: { id: order.id }, context: {})

      expect(result).to be_failure
      expect(CdOrder.find_by(id: order.id)).not_to be_nil
    end
  end
end
