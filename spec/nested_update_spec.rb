# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService nested update" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :nu_orders, force: true do |t|
        t.decimal :total, precision: 10, scale: 2
        t.timestamps null: false
      end

      create_table :nu_lines, force: true do |t|
        t.integer :nu_order_id
        t.integer :qty, null: false
        t.string  :note
        t.timestamps null: false
      end
    end

    Object.const_set(:NuOrder, Class.new(ActiveRecord::Base) { self.table_name = "nu_orders" })
    Object.const_set(:NuLine,  Class.new(ActiveRecord::Base) do
      self.table_name = "nu_lines"
      validates :qty, presence: true
    end)
  end

  after(:all) do
    %i[NuOrder NuLine].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
  end

  before do
    NuOrder.delete_all
    NuLine.delete_all
  end

  let(:nu_line_service) { Class.new(Railsmith::BaseService) { model NuLine } }

  def build_order_service(line_svc)
    Class.new(Railsmith::BaseService) do
      model NuOrder
      has_many :nu_lines, service: line_svc
    end
  end

  def create_order(total: 100.00)
    NuOrder.create!(total: total)
  end

  def create_line(order, qty: 1, note: nil)
    NuLine.create!(nu_order_id: order.id, qty: qty, note: note)
  end

  # =========================================================================
  # 1. Update existing nested item (has id + attributes)
  # =========================================================================

  describe "updating an existing nested item" do
    it "updates the existing child record" do
      svc   = build_order_service(nu_line_service)
      order = create_order
      line  = create_line(order, qty: 1)

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: { total: 200.00 },
          nu_lines: [{ id: line.id, attributes: { qty: 99 } }]
        },
        context: {}
      )

      expect(result).to be_success
      expect(line.reload.qty).to eq(99)
    end

    it "updates the parent record alongside nested updates" do
      svc   = build_order_service(nu_line_service)
      order = create_order(total: 10.00)
      line  = create_line(order)

      svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: { total: 55.00 },
          nu_lines: [{ id: line.id, attributes: { qty: 3 } }]
        },
        context: {}
      )

      expect(order.reload.total.to_f).to eq(55.00)
    end
  end

  # =========================================================================
  # 2. Create new nested item (no id — attributes only)
  # =========================================================================

  describe "creating a new nested item during update" do
    it "creates the new child record with FK injected" do
      svc   = build_order_service(nu_line_service)
      order = create_order

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: {},
          nu_lines: [{ attributes: { qty: 7 } }]
        },
        context: {}
      )

      expect(result).to be_success
      new_line = NuLine.last
      expect(new_line.qty).to eq(7)
      expect(new_line.nu_order_id).to eq(order.id)
    end
  end

  # =========================================================================
  # 3. Destroy nested item (_destroy flag)
  # =========================================================================

  describe "destroying a nested item" do
    it "destroys the child record when _destroy is true" do
      svc   = build_order_service(nu_line_service)
      order = create_order
      line  = create_line(order)

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: {},
          nu_lines: [{ id: line.id, _destroy: true }]
        },
        context: {}
      )

      expect(result).to be_success
      expect(NuLine.find_by(id: line.id)).to be_nil
    end

    it "destroys when _destroy is '1'" do
      svc   = build_order_service(nu_line_service)
      order = create_order
      line  = create_line(order)

      svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: {},
          nu_lines: [{ id: line.id, _destroy: "1" }]
        },
        context: {}
      )

      expect(NuLine.find_by(id: line.id)).to be_nil
    end

    it "destroys when _destroy is 'true'" do
      svc   = build_order_service(nu_line_service)
      order = create_order
      line  = create_line(order)

      svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: {},
          nu_lines: [{ id: line.id, _destroy: "true" }]
        },
        context: {}
      )

      expect(NuLine.find_by(id: line.id)).to be_nil
    end
  end

  # =========================================================================
  # 4. Mixed operations in a single update call
  # =========================================================================

  describe "mixed nested operations" do
    it "updates, creates, and destroys in one call" do
      svc    = build_order_service(nu_line_service)
      order  = create_order
      keep   = create_line(order, qty: 1, note: "keep")
      remove = create_line(order, qty: 2, note: "remove")

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: {},
          nu_lines: [
            { id: keep.id,   attributes: { qty: 10 } }, # update
            { id: remove.id, _destroy: true },             # destroy
            { attributes: { qty: 5 } }                     # create
          ]
        },
        context: {}
      )

      expect(result).to be_success
      expect(keep.reload.qty).to eq(10)
      expect(NuLine.find_by(id: remove.id)).to be_nil
      expect(NuLine.where(qty: 5).count).to eq(1)
    end
  end

  # =========================================================================
  # 5. Nested failure rolls back parent update
  # =========================================================================

  describe "rollback on nested failure" do
    it "rolls back parent attribute update when nested item fails" do
      svc   = build_order_service(nu_line_service)
      order = create_order(total: 10.00)

      result = svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: { total: 999.00 },
          nu_lines: [{ attributes: { qty: nil } }] # qty required → fails
        },
        context: {}
      )

      expect(result).to be_failure
      expect(order.reload.total.to_f).to eq(10.00)
    end
  end

  # =========================================================================
  # 6. No nested params — plain update
  # =========================================================================

  describe "update without nested params" do
    it "updates parent when no nested key is in params" do
      svc   = build_order_service(nu_line_service)
      order = create_order(total: 1.00)

      result = svc.call(
        action: :update,
        params: { id: order.id, attributes: { total: 42.00 } },
        context: {}
      )

      expect(result).to be_success
      expect(order.reload.total.to_f).to eq(42.00)
    end
  end
end
