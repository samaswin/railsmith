# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService CRUD defaults" do
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

  it "creates a record by default" do
    result = service_class.call(action: :create, params: { attributes: { name: "A" } }, context: {})

    expect(result).to be_success
    expect(result.value).to be_a(Widget)
    expect(result.value.name).to eq("A")
    expect(result.value.id).not_to be_nil
  end

  it "returns validation failure for invalid create" do
    result = service_class.call(action: :create, params: { attributes: { name: nil } }, context: {})

    expect(result).to be_failure
    expect(result.code).to eq("validation_error")
    expect(result.error.to_h.fetch(:details)).to have_key(:errors)
  end

  it "updates a record by default" do
    widget = Widget.create!(name: "Old")

    result = service_class.call(action: :update, params: { id: widget.id, attributes: { name: "New" } }, context: {})

    expect(result).to be_success
    expect(result.value.reload.name).to eq("New")
  end

  it "returns not_found for missing record on update" do
    result = service_class.call(action: :update, params: { id: -1, attributes: { name: "X" } }, context: {})

    expect(result).to be_failure
    expect(result.code).to eq("not_found")
  end

  it "destroys a record by default" do
    widget = Widget.create!(name: "Kill")

    result = service_class.call(action: :destroy, params: { id: widget.id }, context: {})

    expect(result).to be_success
    expect(Widget.find_by(id: widget.id)).to be_nil
  end

  it "returns validation failure when id is missing" do
    result = service_class.call(action: :destroy, params: {}, context: {})

    expect(result).to be_failure
    expect(result.code).to eq("validation_error")
    expect(result.error.to_h.fetch(:details)).to eq({ missing: ["id"] })
  end

  it "returns validation failure when id is missing on update" do
    result = service_class.call(action: :update, params: { attributes: { name: "X" } }, context: {})

    expect(result).to be_failure
    expect(result.code).to eq("validation_error")
    expect(result.error.to_h.fetch(:details)).to eq({ missing: ["id"] })
  end

  it "returns conflict failure when a unique constraint is violated" do
    allow_any_instance_of(Widget).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

    result = service_class.call(action: :create, params: { attributes: { name: "Any" } }, context: {})

    expect(result).to be_failure
    expect(result.code).to eq("conflict")
  end

  it "rolls back the transaction and returns failure when an exception occurs during write" do
    count_before = Widget.count
    allow_any_instance_of(Widget).to receive(:save).and_raise(StandardError, "db error")

    result = service_class.call(action: :create, params: { attributes: { name: "TxTest" } }, context: {})

    expect(result).to be_failure
    expect(Widget.count).to eq(count_before)
  end
end
