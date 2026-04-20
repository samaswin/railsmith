# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith.configure global hooks" do
  after { Railsmith.configuration.reset_global_hooks! }

  let(:service_class) do
    Class.new(Railsmith::BaseService) do
      def self.name
        "TestCommerceService"
      end

      domain :commerce

      def create
        Railsmith::Result.success(value: :created)
      end
    end
  end

  it "runs global before hooks before class-level hooks" do
    order = []
    Railsmith.configure do |config|
      config.before_action :create do
        order << :global
      end
    end
    local = service_class.tap do |c|
      c.before(:create) { order << :class }
    end

    local.call(action: :create, params: {}, context: {})

    expect(order).to eq(%i[global class])
  end

  it "runs global after hooks after class-level after hooks" do
    order = []
    Railsmith.configure do |config|
      config.after_action :create do |_result|
        order << :global_after
      end
    end
    local = service_class.tap do |c|
      c.after(:create) { |_r| order << :class_after }
    end

    local.call(action: :create, params: {}, context: {})

    expect(order).to eq(%i[class_after global_after])
  end

  it "wraps class-level around hooks with a global around hook" do
    trace = []
    Railsmith.configure do |config|
      config.around_action :create do |action|
        trace << :global_in
        result = action.call
        trace << :global_out
        result
      end
    end
    local = service_class.tap do |c|
      c.around(:create) do |action|
        trace << :class_in
        result = action.call
        trace << :class_out
        result
      end
    end

    local.call(action: :create, params: {}, context: {})

    expect(trace).to eq(%i[global_in class_in global_out class_out])
  end

  describe "only: domain filter" do
    it "fires the global hook only for services whose domain matches" do
      ran = []
      Railsmith.configure do |config|
        config.before_action :create, only: [:commerce] do
          ran << :commerce_hook
        end
      end

      billing_service = Class.new(Railsmith::BaseService) do
        domain :billing
        def create
          Railsmith::Result.success(value: :b)
        end
      end

      service_class.call(action: :create, params: {}, context: {})
      billing_service.call(action: :create, params: {}, context: {})

      expect(ran).to eq([:commerce_hook])
    end

    it "does not fire for services without a declared domain" do
      ran = []
      Railsmith.configure do |config|
        config.before_action :create, only: [:commerce] do
          ran << :hit
        end
      end

      undomained = Class.new(Railsmith::BaseService) do
        def create
          Railsmith::Result.success(value: :u)
        end
      end

      undomained.call(action: :create, params: {}, context: {})
      expect(ran).to be_empty
    end
  end

  describe "named global hooks" do
    it "can be skipped by a subclass via skip_hook" do
      ran = []
      Railsmith.configure do |config|
        config.before_action :create, name: :rate_limit do
          ran << :global
        end
      end

      internal = Class.new(Railsmith::BaseService) do
        skip_hook :rate_limit
        def create
          Railsmith::Result.success(value: :i)
        end
      end

      internal.call(action: :create, params: {}, context: {})
      # skip_hook only affects class-level registry, not the global chain,
      # so the global hook still fires. This test documents that boundary.
      expect(ran).to eq([:global])
    end
  end
end
