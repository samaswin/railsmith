# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService Association DSL" do
  let(:stub_service) { Class.new(Railsmith::BaseService) }
  let(:other_service) { Class.new(Railsmith::BaseService) }

  # =========================================================================
  # 1. has_many registration
  # =========================================================================

  describe "has_many" do
    it "registers a has_many association in the registry" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { has_many :items, service: stub }

      defn = svc.association_registry[:items]
      expect(defn).not_to be_nil
      expect(defn.kind).to eq(:has_many)
      expect(defn.service_class).to eq(stub)
    end

    it "stores dependent option" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { has_many :items, service: stub, dependent: :destroy }
      expect(svc.association_registry[:items].dependent).to eq(:destroy)
    end

    it "stores validate option" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { has_many :items, service: stub, validate: false }
      expect(svc.association_registry[:items].validate).to be false
    end

    it "stores explicit foreign_key" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { has_many :items, service: stub, foreign_key: :custom_id }
      expect(svc.association_registry[:items].foreign_key).to eq(:custom_id)
    end

    it "defaults dependent to :ignore" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { has_many :items, service: stub }
      expect(svc.association_registry[:items].dependent).to eq(:ignore)
    end
  end

  # =========================================================================
  # 2. has_one registration
  # =========================================================================

  describe "has_one" do
    it "registers a has_one association" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { has_one :profile, service: stub }

      defn = svc.association_registry[:profile]
      expect(defn).not_to be_nil
      expect(defn.kind).to eq(:has_one)
    end

    it "stores dependent and validate options" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) do
        has_one :profile, service: stub, dependent: :nullify, validate: false
      end

      defn = svc.association_registry[:profile]
      expect(defn.dependent).to eq(:nullify)
      expect(defn.validate).to be false
    end
  end

  # =========================================================================
  # 3. belongs_to registration
  # =========================================================================

  describe "belongs_to" do
    it "registers a belongs_to association" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { belongs_to :customer, service: stub }

      defn = svc.association_registry[:customer]
      expect(defn).not_to be_nil
      expect(defn.kind).to eq(:belongs_to)
    end

    it "stores optional flag" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { belongs_to :customer, service: stub, optional: true }
      expect(svc.association_registry[:customer].optional).to be true
    end

    it "defaults optional to false" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) { belongs_to :customer, service: stub }
      expect(svc.association_registry[:customer].optional).to be false
    end
  end

  # =========================================================================
  # 4. AssociationDefinition — FK inference
  # =========================================================================

  describe "inferred_foreign_key" do
    let(:parent_model) { double("Order", name: "Order") }

    it "uses explicit foreign_key when provided" do
      stub = stub_service
      defn = Railsmith::BaseService::AssociationDefinition.new(
        :items, :has_many, service: stub, foreign_key: :explicit_id
      )
      expect(defn.inferred_foreign_key(parent_model)).to eq(:explicit_id)
    end

    it "infers FK from parent model name for has_many" do
      stub = stub_service
      defn = Railsmith::BaseService::AssociationDefinition.new(:items, :has_many, service: stub)
      expect(defn.inferred_foreign_key(parent_model)).to eq(:order_id)
    end

    it "infers FK from parent model name for has_one" do
      stub = stub_service
      defn = Railsmith::BaseService::AssociationDefinition.new(:profile, :has_one, service: stub)
      expect(defn.inferred_foreign_key(parent_model)).to eq(:order_id)
    end

    it "infers FK from association name for belongs_to" do
      stub = stub_service
      defn = Railsmith::BaseService::AssociationDefinition.new(:customer, :belongs_to, service: stub)
      expect(defn.inferred_foreign_key(nil)).to eq(:customer_id)
    end

    it "handles CamelCase model names with underscore inference" do
      stub = stub_service
      model = double("SalesOrder", name: "SalesOrder")
      defn = Railsmith::BaseService::AssociationDefinition.new(:items, :has_many, service: stub)
      expect(defn.inferred_foreign_key(model)).to eq(:sales_order_id)
    end

    it "is frozen after initialization" do
      stub = stub_service
      defn = Railsmith::BaseService::AssociationDefinition.new(:items, :has_many, service: stub)
      expect(defn).to be_frozen
    end
  end

  # =========================================================================
  # 5. AssociationRegistry operations
  # =========================================================================

  describe "AssociationRegistry" do
    let(:registry) { Railsmith::BaseService::AssociationRegistry.new }
    let(:defn) do
      Railsmith::BaseService::AssociationDefinition.new(:items, :has_many, service: stub_service)
    end

    it "starts empty" do
      expect(registry).to be_empty
      expect(registry.any?).to be false
    end

    it "registers a definition" do
      registry.register(defn)
      expect(registry.any?).to be true
      expect(registry[:items]).to eq(defn)
    end

    it "returns all definitions in order" do
      stub = stub_service
      d1 = Railsmith::BaseService::AssociationDefinition.new(:a, :has_many, service: stub)
      d2 = Railsmith::BaseService::AssociationDefinition.new(:b, :has_one,  service: stub)
      registry.register(d1)
      registry.register(d2)
      expect(registry.all.map(&:name)).to eq(%i[a b])
    end

    it "overwrites an existing definition with the same name" do
      stub = stub_service
      d1 = Railsmith::BaseService::AssociationDefinition.new(:items, :has_many, service: stub)
      d2 = Railsmith::BaseService::AssociationDefinition.new(:items, :has_one,  service: stub)
      registry.register(d1)
      registry.register(d2)
      expect(registry[:items].kind).to eq(:has_one)
    end

    it "dups without sharing mutations" do
      registry.register(defn)
      copy = registry.dup

      stub = stub_service
      extra = Railsmith::BaseService::AssociationDefinition.new(:extra, :has_one, service: stub)
      copy.register(extra)

      expect(registry[:extra]).to be_nil
      expect(copy[:extra]).not_to be_nil
    end
  end

  # =========================================================================
  # 6. Inheritance
  # =========================================================================

  describe "inheritance" do
    let(:parent) do
      stub = stub_service
      other = other_service
      Class.new(Railsmith::BaseService) do
        has_many   :items,   service: stub
        belongs_to :account, service: other
      end
    end

    it "subclass inherits parent associations" do
      child = Class.new(parent)
      expect(child.association_registry[:items]).not_to be_nil
      expect(child.association_registry[:account]).not_to be_nil
    end

    it "subclass can add associations without affecting parent" do
      stub = stub_service
      child = Class.new(parent) { has_one :profile, service: stub }

      expect(child.association_registry[:profile]).not_to be_nil
      expect(parent.association_registry[:profile]).to be_nil
    end

    it "subclass can override a parent association" do
      stub = stub_service
      child = Class.new(parent) { has_many :items, service: stub, dependent: :destroy }

      expect(child.association_registry[:items].dependent).to eq(:destroy)
      expect(parent.association_registry[:items].dependent).to eq(:ignore)
    end
  end

  # =========================================================================
  # 7. Multiple associations registered in declaration order
  # =========================================================================

  describe "multiple associations" do
    it "stores all three macro types together" do
      stub = stub_service
      svc = Class.new(Railsmith::BaseService) do
        has_many   :lines,    service: stub
        has_one    :header,   service: stub
        belongs_to :customer, service: stub
      end

      names = svc.association_registry.all.map(&:name)
      expect(names).to contain_exactly(:lines, :header, :customer)
    end
  end
end
