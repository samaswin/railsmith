# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService nested create" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :nc_orders, force: true do |t|
        t.decimal :total, precision: 10, scale: 2
        t.timestamps null: false
      end

      create_table :nc_lines, force: true do |t|
        t.integer :nc_order_id
        t.integer :qty, null: false
        t.timestamps null: false
      end

      create_table :nc_notes, force: true do |t|
        t.integer :nc_order_id
        t.string  :content
        t.timestamps null: false
      end
    end

    Object.const_set(:NcOrder, Class.new(ActiveRecord::Base) { self.table_name = "nc_orders" })
    Object.const_set(:NcLine,  Class.new(ActiveRecord::Base) do
      self.table_name = "nc_lines"
      validates :qty, presence: true
    end)
    Object.const_set(:NcNote,  Class.new(ActiveRecord::Base) { self.table_name = "nc_notes" })
  end

  after(:all) do
    %i[NcOrder NcLine NcNote].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
  end

  before { NcOrder.delete_all; NcLine.delete_all; NcNote.delete_all }

  let(:nc_line_service)  { Class.new(Railsmith::BaseService) { model NcLine } }
  let(:nc_note_service)  { Class.new(Railsmith::BaseService) { model NcNote } }

  def build_order_service(line_svc, note_svc = nil)
    Class.new(Railsmith::BaseService) do
      model NcOrder
      has_many :nc_lines, service: line_svc
      has_one  :nc_note,  service: note_svc if note_svc
    end
  end

  # =========================================================================
  # 1. has_many nested create
  # =========================================================================

  describe "has_many nested create" do
    it "creates the parent and all nested items" do
      svc = build_order_service(nc_line_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 99.99 },
          nc_lines: [
            { attributes: { qty: 2 } },
            { attributes: { qty: 5 } }
          ]
        },
        context: {}
      )

      expect(result).to be_success
      expect(NcOrder.count).to eq(1)
      expect(NcLine.count).to eq(2)
    end

    it "injects parent FK into each nested item" do
      svc = build_order_service(nc_line_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 10.00 },
          nc_lines: [{ attributes: { qty: 1 } }]
        },
        context: {}
      )

      order = result.value
      line  = NcLine.first
      expect(line.nc_order_id).to eq(order.id)
    end

    it "returns success with nested meta when items are created" do
      svc = build_order_service(nc_line_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 5.00 },
          nc_lines: [{ attributes: { qty: 3 } }, { attributes: { qty: 4 } }]
        },
        context: {}
      )

      expect(result).to be_success
      meta = result.meta.dig(:nested, :nc_lines)
      expect(meta).to include(total: 2, success_count: 2, failure_count: 0)
    end

    it "rolls back parent when a nested item fails" do
      svc = build_order_service(nc_line_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 1.00 },
          nc_lines: [{ attributes: { qty: nil } }]  # qty is required
        },
        context: {}
      )

      expect(result).to be_failure
      expect(NcOrder.count).to eq(0)
      expect(NcLine.count).to eq(0)
    end

    it "creates parent only when no nested params are provided" do
      svc = build_order_service(nc_line_service)

      result = svc.call(
        action: :create,
        params: { attributes: { total: 20.00 } },
        context: {}
      )

      expect(result).to be_success
      expect(NcOrder.count).to eq(1)
      expect(NcLine.count).to eq(0)
    end

    it "creates parent only when nested array is empty" do
      svc = build_order_service(nc_line_service)

      result = svc.call(
        action: :create,
        params: { attributes: { total: 20.00 }, nc_lines: [] },
        context: {}
      )

      expect(result).to be_success
      expect(NcLine.count).to eq(0)
    end
  end

  # =========================================================================
  # 2. has_one nested create
  # =========================================================================

  describe "has_one nested create" do
    it "creates the parent and the single nested record" do
      svc = build_order_service(nc_line_service, nc_note_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 50.00 },
          nc_note: { attributes: { content: "priority" } }
        },
        context: {}
      )

      expect(result).to be_success
      expect(NcNote.count).to eq(1)
    end

    it "injects parent FK into the has_one record" do
      svc = build_order_service(nc_line_service, nc_note_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 50.00 },
          nc_note: { attributes: { content: "urgent" } }
        },
        context: {}
      )

      note = NcNote.first
      expect(note.nc_order_id).to eq(result.value.id)
    end

    it "rolls back parent when has_one nested record fails" do
      failing_note_svc = Class.new(Railsmith::BaseService) do
        model NcNote
        def create
          Railsmith::Result.failure(
            error: Railsmith::Errors.validation_error(message: "Note invalid")
          )
        end
      end

      svc = build_order_service(nc_line_service, failing_note_svc)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 50.00 },
          nc_note: { attributes: { content: "bad" } }
        },
        context: {}
      )

      expect(result).to be_failure
      expect(NcOrder.count).to eq(0)
    end
  end

  # =========================================================================
  # 3. No associations declared — no nested writes attempted
  # =========================================================================

  describe "service without associations" do
    it "creates parent normally and ignores any nested keys in params" do
      plain_svc = Class.new(Railsmith::BaseService) { model NcOrder }

      result = plain_svc.call(
        action: :create,
        params: { attributes: { total: 7.00 }, nc_lines: [{ attributes: { qty: 1 } }] },
        context: {}
      )

      expect(result).to be_success
      expect(NcLine.count).to eq(0)
    end
  end
end
