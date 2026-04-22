# frozen_string_literal: true

require "spec_helper"

# End-to-end rollback scenarios modelled after a checkout flow where payment
# failure must trigger inventory unreservation.
RSpec.describe "Pipeline rollback integration — CheckoutPipeline with compensation" do
  after { Railsmith::Instrumentation.reset! }

  # ---------------------------------------------------------------------------
  # Domain stub services — with rollback actions
  # ---------------------------------------------------------------------------

  let(:cart_service) do
    Class.new(Railsmith::BaseService) do
      def validate
        return Railsmith::Result.failure(code: :validation_error, message: "Cart is empty") if params[:cart_id].nil?

        Railsmith::Result.success(value: { cart_total: 150, item_count: 3 })
      end
    end
  end

  # InventoryService records calls so specs can verify rollback was invoked.
  let(:inventory_calls) { [] }

  let(:inventory_service) do
    calls = inventory_calls
    Class.new(Railsmith::BaseService) do
      define_method(:reserve) do
        return Railsmith::Result.failure(code: :conflict, message: "Out of stock") if params[:out_of_stock]

        calls << { action: :reserve, params: params.dup }
        Railsmith::Result.success(value: { reservation_id: "rsv-001" })
      end

      define_method(:unreserve) do
        calls << { action: :unreserve, params: params.dup }
        Railsmith::Result.success
      end
    end
  end

  let(:payment_calls) { [] }

  let(:payment_service) do
    calls = payment_calls
    Class.new(Railsmith::BaseService) do
      define_method(:charge) do
        return Railsmith::Result.failure(code: :unauthorized, message: "Card declined") if params[:decline]

        calls << { action: :charge, params: params.dup }
        Railsmith::Result.success(value: { payment_id: "pay-abc" })
      end

      define_method(:refund) do
        calls << { action: :refund, params: params.dup }
        Railsmith::Result.success
      end
    end
  end

  let(:notification_service) do
    Class.new(Railsmith::BaseService) do
      def send_receipt
        Railsmith::Result.success(value: { email_sent: true })
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline under test — with rollback handlers
  # ---------------------------------------------------------------------------

  def checkout_pipeline(cart:, inventory:, payment:, notification:)
    Class.new(Railsmith::Pipeline) do
      step :validate_cart,     service: cart,         action: :validate
      step :reserve_inventory, service: inventory,    action: :reserve, rollback: :unreserve
      step :charge_payment,    service: payment,      action: :charge,
                               inputs: { amount: :cart_total }, rollback: :refund
      step :send_confirmation, service: notification, action: :send_receipt
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — no rollbacks triggered
  # ---------------------------------------------------------------------------

  describe "happy path" do
    it "returns success and does not invoke any rollback" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 42, user_id: 7 })
      expect(result).to be_success

      rollback_actions = (inventory_calls + payment_calls).map { |c| c[:action] }
      expect(rollback_actions).not_to include(:unreserve, :refund)
    end
  end

  # ---------------------------------------------------------------------------
  # Payment failure — triggers inventory rollback, not payment rollback
  # ---------------------------------------------------------------------------

  describe "payment failure" do
    it "returns a failure result" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, user_id: 2, decline: true })
      expect(result).to be_failure
      expect(result.error.message).to eq("Card declined")
      expect(result.meta[:pipeline_step]).to eq(:charge_payment)
    end

    it "invokes :unreserve on InventoryService (reverse order)" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      pipeline.call(params: { cart_id: 1, user_id: 2, decline: true })

      unreserve_calls = inventory_calls.select { |c| c[:action] == :unreserve }
      expect(unreserve_calls.size).to eq(1)
    end

    it "passes reservation_id to the unreserve rollback handler" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      pipeline.call(params: { cart_id: 1, user_id: 2, decline: true })

      unreserve_call = inventory_calls.find { |c| c[:action] == :unreserve }
      expect(unreserve_call[:params]).to include(reservation_id: "rsv-001")
    end

    it "does not invoke :refund on PaymentService (payment was the failing step)" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      pipeline.call(params: { cart_id: 1, user_id: 2, decline: true })

      refund_calls = payment_calls.select { |c| c[:action] == :refund }
      expect(refund_calls).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Inventory failure — no completed steps have rollback, so nothing rolls back
  # ---------------------------------------------------------------------------

  describe "inventory failure" do
    it "returns failure at :reserve_inventory and triggers no rollbacks" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, out_of_stock: true })
      expect(result).to be_failure
      expect(result.meta[:pipeline_step]).to eq(:reserve_inventory)

      all_calls = inventory_calls + payment_calls
      expect(all_calls.map { |c| c[:action] }).not_to include(:unreserve, :refund)
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback failure during compensation — surfaces in result meta
  # ---------------------------------------------------------------------------

  describe "rollback failure during compensation" do
    let(:flaky_inventory_service) do
      Class.new(Railsmith::BaseService) do
        def reserve
          Railsmith::Result.success(value: { reservation_id: "rsv-002" })
        end

        def unreserve
          Railsmith::Result.failure(code: :unexpected, message: "DB unavailable during rollback")
        end
      end
    end

    it "still returns the primary failure" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: flaky_inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, decline: true })
      expect(result.error.message).to eq("Card declined")
    end

    it "surfaces the rollback failure in :rollback_failures meta" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: flaky_inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, decline: true })

      failures = result.meta[:rollback_failures]
      expect(failures).to be_an(Array)
      expect(failures.size).to eq(1)
      expect(failures.first[:step]).to eq(:reserve_inventory)
      expect(failures.first[:error].message).to eq("DB unavailable during rollback")
    end
  end

  # ---------------------------------------------------------------------------
  # Instrumentation — rollback events emitted
  # ---------------------------------------------------------------------------

  describe "instrumentation" do
    it "emits pipeline.rollback.railsmith events for each rollback invoked" do
      rollback_events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| rollback_events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      pipeline.call(params: { cart_id: 1, decline: true })

      expect(rollback_events.size).to eq(1)
      expect(rollback_events.first[:step]).to eq(:reserve_inventory)
      expect(rollback_events.first[:status]).to eq(:success)
    end

    it "emits no rollback events when the pipeline succeeds" do
      rollback_events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| rollback_events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      pipeline.call(params: { cart_id: 1, user_id: 2 })
      expect(rollback_events).to be_empty
    end
  end
end
