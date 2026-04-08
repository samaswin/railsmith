# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService belongs_to nested write" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :btw_customers, force: true do |t|
        t.string :name, null: false
        t.timestamps null: false
      end

      create_table :btw_orders, force: true do |t|
        t.integer :btw_customer_id
        t.string  :number, null: false
        t.timestamps null: false
      end
    end

    Object.const_set(:BtwCustomer, Class.new(ActiveRecord::Base) { self.table_name = "btw_customers" })
    Object.const_set(:BtwOrder, Class.new(ActiveRecord::Base) do
      self.table_name = "btw_orders"
      belongs_to :btw_customer, class_name: "BtwCustomer", optional: true
    end)
  end

  after(:all) do
    %i[BtwCustomer BtwOrder].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
  end

  before do
    BtwOrder.delete_all
    BtwCustomer.delete_all
  end

  let(:customer_service) { Class.new(Railsmith::BaseService) { model BtwCustomer } }

  def build_order_service(customer_svc)
    Class.new(Railsmith::BaseService) do
      model BtwOrder
      belongs_to :btw_customer, service: customer_svc, optional: true
    end
  end

  describe "nested create on parent create" do
    it "creates the belongs_to record and assigns the FK on the parent" do
      svc = build_order_service(customer_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { number: "A-1" },
          btw_customer: { attributes: { name: "Alice" } }
        },
        context: {}
      )

      expect(result).to be_success
      order = result.value
      expect(order.btw_customer_id).to be_present
      expect(BtwCustomer.count).to eq(1)
      expect(BtwCustomer.first.name).to eq("Alice")
    end
  end

  describe "nested update on parent update" do
    it "updates the belongs_to record when id is provided" do
      svc = build_order_service(customer_service)
      customer = BtwCustomer.create!(name: "Old")
      order = BtwOrder.create!(number: "A-2", btw_customer_id: customer.id)

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: { number: "A-2" },
          btw_customer: { id: customer.id, attributes: { name: "New" } }
        },
        context: {}
      )

      expect(result).to be_success
      expect(customer.reload.name).to eq("New")
      expect(order.reload.btw_customer_id).to eq(customer.id)
    end
  end

  describe "nested destroy on parent update" do
    it "destroys the belongs_to record and nullifies the FK on the parent when _destroy is true" do
      svc = build_order_service(customer_service)
      customer = BtwCustomer.create!(name: "To Delete")
      order = BtwOrder.create!(number: "A-3", btw_customer_id: customer.id)

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: { number: "A-3" },
          btw_customer: { id: customer.id, _destroy: true }
        },
        context: {}
      )

      expect(result).to be_success
      expect(BtwCustomer.find_by(id: customer.id)).to be_nil
      expect(order.reload.btw_customer_id).to be_nil
    end
  end
end
