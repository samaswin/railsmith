# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService bulk defaults" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :widgets, force: true do |t|
        t.string :name, null: false
        t.timestamps null: false
      end
    end

    widget_class = Class.new(ActiveRecord::Base) do
      self.table_name = "widgets"
      validates :name, presence: true
    end

    Object.const_set(:Widget, widget_class)
  end

  after(:all) do
    Object.send(:remove_const, :Widget) if Object.const_defined?(:Widget)
  end

  let(:service_class) do
    Class.new(Railsmith::BaseService) do
      model Widget
    end
  end

  before do
    Widget.delete_all
  end

  describe "bulk_create" do
    it "creates multiple records in best_effort mode" do
      result =
        service_class.call(
          action: :bulk_create,
          params: {
            transaction_mode: :best_effort,
            items: [{ name: "A" }, { name: "B" }]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(total: 2, success_count: 2, failure_count: 0, all_succeeded: true)
      expect(Widget.count).to eq(2)
    end

    it "returns item-level errors and persists successes in best_effort mode" do
      result =
        service_class.call(
          action: :bulk_create,
          params: {
            transaction_mode: :best_effort,
            items: [{ name: "Ok" }, { name: nil }]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(
        total: 2,
        success_count: 1,
        failure_count: 1,
        all_succeeded: false
      )
      expect(result.value.fetch(:items).map { |item| item.fetch(:success) }).to contain_exactly(true, false)
      expect(Widget.where(name: "Ok").count).to eq(1)
    end

    it "rolls back all writes in all_or_nothing mode when any item fails" do
      result =
        service_class.call(
          action: :bulk_create,
          params: {
            transaction_mode: :all_or_nothing,
            items: [{ name: "Ok" }, { name: nil }]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(
        total: 2,
        success_count: 1,
        failure_count: 1,
        all_succeeded: false
      )
      expect(Widget.where(name: "Ok").count).to eq(0)
    end

    it "returns empty results for empty input" do
      result = service_class.call(action: :bulk_create, params: { items: [] }, context: {})

      expect(result).to be_success
      expect(result.value.fetch(:items)).to eq([])
      expect(result.value.fetch(:summary)).to include(total: 0, success_count: 0, failure_count: 0, all_succeeded: true)
    end

    it "returns validation failure when input exceeds limit" do
      result =
        service_class.call(
          action: :bulk_create,
          params: { limit: 1, items: [{ name: "A" }, { name: "B" }] },
          context: {}
        )

      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.to_h).to include(message: "Bulk limit exceeded")
    end
  end

  describe "bulk_update" do
    it "updates multiple records" do
      first = Widget.create!(name: "Old1")
      second = Widget.create!(name: "Old2")

      result =
        service_class.call(
          action: :bulk_update,
          params: {
            transaction_mode: :best_effort,
            items: [
              { id: first.id, attributes: { name: "New1" } },
              { id: second.id, attributes: { name: "New2" } }
            ]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(total: 2, success_count: 2, failure_count: 0, all_succeeded: true)
      expect(first.reload.name).to eq("New1")
      expect(second.reload.name).to eq("New2")
    end

    it "does not update any records in all_or_nothing mode when any item fails" do
      first = Widget.create!(name: "Old1")
      second = Widget.create!(name: "Old2")

      result =
        service_class.call(
          action: :bulk_update,
          params: {
            transaction_mode: :all_or_nothing,
            items: [
              { id: first.id, attributes: { name: "New1" } },
              { id: second.id, attributes: { name: nil } }
            ]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(
        total: 2,
        success_count: 1,
        failure_count: 1,
        all_succeeded: false
      )
      expect(first.reload.name).to eq("Old1")
      expect(second.reload.name).to eq("Old2")
    end
  end

  describe "bulk_destroy" do
    it "destroys multiple records" do
      first = Widget.create!(name: "A")
      second = Widget.create!(name: "B")

      result =
        service_class.call(
          action: :bulk_destroy,
          params: {
            transaction_mode: :best_effort,
            items: [first.id, second.id]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(total: 2, success_count: 2, failure_count: 0, all_succeeded: true)
      expect(Widget.find_by(id: first.id)).to be_nil
      expect(Widget.find_by(id: second.id)).to be_nil
    end

    it "does not destroy any records in all_or_nothing mode when any item fails" do
      first = Widget.create!(name: "A")
      second = Widget.create!(name: "B")

      result =
        service_class.call(
          action: :bulk_destroy,
          params: {
            transaction_mode: :all_or_nothing,
            items: [first.id, -1, second.id]
          },
          context: {}
        )

      expect(result).to be_success
      expect(result.value.fetch(:summary)).to include(
        total: 3,
        success_count: 2,
        failure_count: 1,
        all_succeeded: false
      )
      expect(Widget.find_by(id: first.id)).not_to be_nil
      expect(Widget.find_by(id: second.id)).not_to be_nil
    end
  end
end
