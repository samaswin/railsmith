# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "railsmith"
require "generators/railsmith/model_service/model_service_generator"

RSpec.describe Railsmith::Generators::ModelServiceGenerator do
  def run_generator(args, destination_root)
    described_class.start(args, destination_root: destination_root)
  end

  it "generates a service for a single model with no namespace wrapper" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/services/user_service.rb"))
    end
  end

  it "does not wrap the class in any module by default" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/user_service.rb"))
      expect(content).not_to include("module ")
      expect(content).to include("class UserService < Railsmith::BaseService")
    end
  end

  it "generates a service for a namespaced model under its own namespace path" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["Admin::User"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/services/admin/user_service.rb"))
    end
  end

  it "generates a service with --namespace wrapping and domain from first segment" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["Invoice", "--namespace=Billing::Services"], temp_dir)

      expect(File).to exist(
        File.join(temp_dir, "app/services/billing/services/invoice_service.rb")
      )
      content = File.read(File.join(temp_dir, "app/services/billing/services/invoice_service.rb"))
      expect(content).to include("module Billing")
      expect(content).to include("module Services")
      expect(content).to include("class InvoiceService < Railsmith::BaseService")
      expect(content).to include("domain :billing")
    end
  end

  it "generates a service in domain mode under app/domains" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["Billing::Invoice", "--domain=Billing"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/domains/billing/services/invoice_service.rb"))
      content = File.read(File.join(temp_dir, "app/domains/billing/services/invoice_service.rb"))
      expect(content).to include("module Billing")
      expect(content).to include("module Services")
    end
  end

  it "is idempotent when run twice" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)
      initial_content = File.read(File.join(temp_dir, "app/services/user_service.rb"))

      run_generator(["User"], temp_dir)
      second_content = File.read(File.join(temp_dir, "app/services/user_service.rb"))

      expect(second_content).to eq(initial_content)
    end
  end

  it "does not overwrite without --force" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)
      file = File.join(temp_dir, "app/services/user_service.rb")
      File.write(file, "CUSTOM\n")

      run_generator(["User"], temp_dir)

      expect(File.read(file)).to eq("CUSTOM\n")
    end
  end

  it "supports a custom output path" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User", "--output-path=app/services/custom_ops"], temp_dir)

      expect(File).to exist(File.join(temp_dir, "app/services/custom_ops/user_service.rb"))
    end
  end

  it "supports optional action stubs" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User", "--actions=create", "update"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/user_service.rb"))
      expect(content).to include("def create")
      expect(content).to include("def update")
      expect(content).not_to include("def destroy")
    end
  end

  it "generates a callable class" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      class ::User
        def self.transaction
          yield
        end

        def self.find_by(*)
          nil
        end

        attr_reader :errors

        def initialize(attributes = {})
          @attributes = attributes
          @persisted = false
          @destroyed = false
          @errors = []
        end

        def assign_attributes(attributes)
          @attributes.merge!(attributes)
        end

        def save
          @persisted = true
        end

        def destroy
          @destroyed = true
        end

        def persisted?
          @persisted
        end

        def destroyed?
          @destroyed
        end
      end

      load File.join(temp_dir, "app/services/user_service.rb")

      result = UserService.call(action: :create, params: { attributes: { name: "A" } })
      expect(result).to be_a(Railsmith::Result)
      expect(result).to be_success
    ensure
      Object.send(:remove_const, :User) if Object.const_defined?(:User)
      Object.send(:remove_const, :UserService) if Object.const_defined?(:UserService)
    end
  end

  # ── Phase 4: --inputs flag ──────────────────────────────────────────────────

  it "generates explicit input declarations with --inputs" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User", "--inputs=email:string:required", "name:string", "age:integer"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/user_service.rb"))
      expect(content).to include("# -- Inputs --")
      expect(content).to include("input :email, String, required: true")
      expect(content).to include("input :name, String")
      expect(content).to include("input :age, Integer")
      expect(content).not_to include("input :age, Integer, required: true")
    end
  end

  it "maps all supported column types in explicit --inputs specs" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(
        [
          "Product",
          "--inputs=price:decimal",
          "active:boolean",
          "ratio:float",
          "born_on:date",
          "sent_at:datetime",
          "meta:json"
        ],
        temp_dir
      )

      content = File.read(File.join(temp_dir, "app/services/product_service.rb"))
      expect(content).to include("input :price, BigDecimal")
      expect(content).to include("input :active, :boolean")
      expect(content).to include("input :ratio, Float")
      expect(content).to include("input :born_on, Date")
      expect(content).to include("input :sent_at, DateTime")
      expect(content).to include("input :meta, Hash")
    end
  end

  it "falls back to String for unknown types in explicit --inputs specs" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["Widget", "--inputs=code:uuid"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/widget_service.rb"))
      expect(content).to include("input :code, String")
    end
  end

  it "omits the Inputs block when --inputs is not given" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/user_service.rb"))
      expect(content).not_to include("# -- Inputs --")
      expect(content).not_to include("input ")
    end
  end

  it "introspects model columns when --inputs is given with no values" do
    columns = {
      "id"         => double(type: :integer),
      "email"      => double(type: :string),
      "age"        => double(type: :integer),
      "created_at" => double(type: :datetime),
      "updated_at" => double(type: :datetime)
    }
    stub_model = Class.new do
      define_singleton_method(:columns_hash) { columns }
    end

    stub_const("IntrospectedUser", stub_model)

    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["IntrospectedUser", "--inputs"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/introspected_user_service.rb"))
      expect(content).to include("# -- Inputs --")
      expect(content).to include("input :email, String")
      expect(content).to include("input :age, Integer")
      expect(content).not_to include("input :id,")
      expect(content).not_to include("input :created_at,")
      expect(content).not_to include("input :updated_at,")
    end
  end

  it "generates no inputs when model cannot be loaded for introspection" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["NonExistentModel", "--inputs"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/non_existent_model_service.rb"))
      expect(content).not_to include("# -- Inputs --")
      expect(content).not_to include("input ")
    end
  end

  # ── Phase 4: --associations flag ─────────────────────────────────────────────

  it "introspects model associations when --associations is given" do
    line_items_reflection = double(macro: :has_many, name: :line_items)
    address_reflection    = double(macro: :has_one,  name: :shipping_address)
    customer_reflection   = double(macro: :belongs_to, name: :customer)

    stub_model = Class.new do
      define_singleton_method(:reflect_on_all_associations) do
        [line_items_reflection, address_reflection, customer_reflection]
      end
    end

    stub_const("AssocOrder", stub_model)

    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["AssocOrder", "--associations"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/assoc_order_service.rb"))
      expect(content).to include("# -- Associations --")
      expect(content).to include("has_many :line_items, service: LineItemService")
      expect(content).to include("has_one :shipping_address, service: ShippingAddressService")
      expect(content).to include("belongs_to :customer, service: CustomerService")
      expect(content).to include("includes :line_items, :shipping_address, :customer")
    end
  end

  it "adds TODO comments for service classes that are not yet defined" do
    reflection = double(macro: :has_many, name: :widgets)
    stub_model = Class.new do
      define_singleton_method(:reflect_on_all_associations) { [reflection] }
    end

    stub_const("TodoModel", stub_model)

    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["TodoModel", "--associations"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/todo_model_service.rb"))
      expect(content).to include("# TODO: Define WidgetService")
      expect(content).to include("has_many :widgets, service: WidgetService")
    end
  end

  it "omits TODO comment when the associated service class is already defined" do
    stub_const("WidgetService", Class.new)
    reflection = double(macro: :has_many, name: :widgets)
    stub_model = Class.new do
      define_singleton_method(:reflect_on_all_associations) { [reflection] }
    end

    stub_const("ModelWithKnownService", stub_model)

    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["ModelWithKnownService", "--associations"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/model_with_known_service_service.rb"))
      expect(content).not_to include("# TODO:")
      expect(content).to include("has_many :widgets, service: WidgetService")
    end
  end

  it "omits the Associations block when --associations is not given" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["User"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/user_service.rb"))
      expect(content).not_to include("# -- Associations --")
      expect(content).not_to include("has_many ")
      expect(content).not_to include("includes ")
    end
  end

  it "generates no associations when model cannot be loaded" do
    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["GhostModel", "--associations"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/ghost_model_service.rb"))
      expect(content).not_to include("# -- Associations --")
    end
  end

  # ── Phase 4: combined --inputs --associations ────────────────────────────────

  it "generates both input and association blocks when both flags are given" do
    reflection = double(macro: :has_many, name: :items)
    columns    = { "id" => double(type: :integer), "name" => double(type: :string) }
    stub_model = Class.new do
      define_singleton_method(:columns_hash) { columns }
      define_singleton_method(:reflect_on_all_associations) { [reflection] }
    end

    stub_const("ComboModel", stub_model)

    Dir.mktmpdir("railsmith-model-generator-spec") do |temp_dir|
      run_generator(["ComboModel", "--inputs", "--associations"], temp_dir)

      content = File.read(File.join(temp_dir, "app/services/combo_model_service.rb"))
      expect(content).to include("# -- Inputs --")
      expect(content).to include("input :name, String")
      expect(content).to include("# -- Associations --")
      expect(content).to include("has_many :items, service: ItemService")
      expect(content).to include("includes :items")
    end
  end
end
