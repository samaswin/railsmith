# frozen_string_literal: true

require "spec_helper"

# End-to-end scenarios that mirror real-world hook usage: audit logging,
# event publishing, and performance timing via around hooks.
RSpec.describe "lifecycle hook integration patterns" do
  after { Railsmith.configuration.reset_global_hooks! }

  describe "audit logging via before hooks" do
    it "records every mutating call with actor and action metadata" do
      audit_store = []

      service = Class.new(Railsmith::BaseService) do
        before :create, :update do
          # Hook body runs in the service instance context.
          ::AUDIT_SINK << {
            service: self.class.name || "anon",
            actor: context[:actor_id],
            action: :current
          }
        end

        def create
          Railsmith::Result.success(value: { id: 1 })
        end

        def update
          Railsmith::Result.success(value: { id: 1, updated: true })
        end
      end

      stub_const("AUDIT_SINK", audit_store)

      service.call(action: :create, params: {}, context: { actor_id: 7 })
      service.call(action: :update, params: {}, context: { actor_id: 7 })

      expect(audit_store.map { |e| e[:actor] }).to eq([7, 7])
    end
  end

  describe "event publishing via after hooks" do
    it "publishes only on success" do
      bus = []

      service = Class.new(Railsmith::BaseService) do
        after :create do |result|
          ::EVENT_BUS << { topic: "created", payload: result.value } if result.success?
        end

        def create
          if params[:boom]
            Railsmith::Result.failure(message: "boom")
          else
            Railsmith::Result.success(value: { id: 42 })
          end
        end
      end

      stub_const("EVENT_BUS", bus)

      service.call(action: :create, params: { boom: true }, context: {})
      service.call(action: :create, params: { boom: false }, context: {})

      expect(bus).to eq([{ topic: "created", payload: { id: 42 } }])
    end
  end

  describe "performance timing via around hooks" do
    it "captures duration around the action call" do
      measurements = []

      service = Class.new(Railsmith::BaseService) do
        around :create do |action|
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = action.call
          dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
          ::TIMINGS << dt
          result
        end

        def create
          Railsmith::Result.success(value: :ok)
        end
      end

      stub_const("TIMINGS", measurements)

      service.call(action: :create, params: {}, context: {})
      expect(measurements.size).to eq(1)
      expect(measurements.first).to be >= 0
    end
  end

  describe "hook + inputs + CRUD interaction" do
    it "does not break input resolution when hooks are declared" do
      seen_params = nil

      service = Class.new(Railsmith::BaseService) do
        input :email, String, required: true

        before :do_it do |params|
          # params argument reflects the service's current @params
          ::HOOK_CAPTURE[:params] = params
        end

        def do_it
          Railsmith::Result.success(value: params)
        end
      end

      stub_const("HOOK_CAPTURE", seen_params = {})

      result = service.call(action: :do_it, params: { email: "jane@doe.org" }, context: {})

      expect(result).to be_success
      expect(result.value).to eq({ email: "jane@doe.org" })
      expect(seen_params[:params]).to eq({ email: "jane@doe.org" })
    end

    it "returns a validation failure without invoking hooks when inputs are missing" do
      ran = []
      service = Class.new(Railsmith::BaseService) do
        input :email, String, required: true

        before :do_it do
          ran << :before
        end

        def do_it
          Railsmith::Result.success(value: :ok)
        end
      end

      result = service.call(action: :do_it, params: {}, context: {})
      expect(result).to be_failure
      expect(ran).to be_empty
    end
  end
end
