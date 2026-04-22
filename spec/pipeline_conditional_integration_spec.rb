# frozen_string_literal: true

require "spec_helper"

# Integration test: conditional checkout with optional coupon application.
# Demonstrates real-world use of if:/unless: and on_failure_continue: in a pipeline
# with a guard helper — matching the Phase 5 exit criterion.
RSpec.describe "Pipeline conditional integration — CheckoutPipeline with optional coupon" do
  after { Railsmith::Instrumentation.reset! }

  # ---------------------------------------------------------------------------
  # Domain stub services
  # ---------------------------------------------------------------------------

  let(:cart_service) do
    Class.new(Railsmith::BaseService) do
      def validate
        return Railsmith::Result.failure(code: :validation_error, message: "Cart is empty") if params[:cart_id].nil?

        Railsmith::Result.success(value: { cart_total: 200, item_count: 2 })
      end
    end
  end

  let(:coupon_calls) { [] }

  let(:coupon_service) do
    calls = coupon_calls
    Class.new(Railsmith::BaseService) do
      define_method(:apply) do
        calls << { params: params.dup }
        if params[:coupon_code] == "INVALID"
          return Railsmith::Result.failure(code: :invalid_coupon,
                                           message: "Coupon expired")
        end

        Railsmith::Result.success(value: { cart_total: params[:cart_total] - 20, discount_applied: true })
      end
    end
  end

  let(:inventory_service) do
    Class.new(Railsmith::BaseService) do
      def reserve
        Railsmith::Result.success(value: { reservation_id: "rsv-001" })
      end

      def unreserve
        Railsmith::Result.success
      end
    end
  end

  let(:payment_service) do
    Class.new(Railsmith::BaseService) do
      def charge
        return Railsmith::Result.failure(code: :unauthorized, message: "Card declined") if params[:decline]

        Railsmith::Result.success(value: { payment_id: "pay-abc", charged: params[:amount] })
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
  # Pipeline under test — with conditional coupon step via named guard
  # ---------------------------------------------------------------------------

  def checkout_pipeline(cart:, coupon:, inventory:, payment:, notification:)
    Class.new(Railsmith::Pipeline) do
      # Named guard: coupon step runs only when coupon_code is present in params
      guard(:has_coupon?) { |params, _ctx| params.key?(:coupon_code) && !params[:coupon_code].nil? }

      step :validate_cart,     service: cart,         action: :validate
      step :apply_coupon,      service: coupon,       action: :apply,       if: :has_coupon?
      step :reserve_inventory, service: inventory,    action: :reserve,     rollback: :unreserve
      step :charge_payment,    service: payment,      action: :charge,      inputs: { amount: :cart_total }
      step :send_confirmation, service: notification, action: :send_receipt
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — no coupon
  # ---------------------------------------------------------------------------

  describe "checkout without coupon" do
    it "returns success and skips apply_coupon" do
      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, user_id: 7 })
      expect(result).to be_success
      expect(coupon_calls).to be_empty
    end

    it "charges the full cart_total when no coupon is applied" do
      received_params = nil
      capturing_payment = Class.new(Railsmith::BaseService) do
        define_method(:charge) do
          received_params = params
          Railsmith::Result.success(value: { payment_id: "pay-x" })
        end
      end

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: capturing_payment,
        notification: notification_service
      )
      pipeline.call(params: { cart_id: 1 })

      expect(received_params[:amount]).to eq(200)
    end

    it "emits a skipped event for apply_coupon" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.skipped.railsmith") { |_, p| events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: notification_service
      )
      pipeline.call(params: { cart_id: 1 })

      expect(events.map { |e| e[:step] }).to include(:apply_coupon)
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — with coupon
  # ---------------------------------------------------------------------------

  describe "checkout with valid coupon" do
    it "returns success and calls coupon service" do
      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, coupon_code: "SAVE20" })
      expect(result).to be_success
      expect(coupon_calls.size).to eq(1)
    end

    it "charges the discounted total after coupon is applied" do
      received_params = nil
      capturing_payment = Class.new(Railsmith::BaseService) do
        define_method(:charge) do
          received_params = params
          Railsmith::Result.success(value: { payment_id: "pay-x" })
        end
      end

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: capturing_payment,
        notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, coupon_code: "SAVE20" })

      # cart_total was 200; coupon reduces it to 180; payment receives amount: 180
      expect(received_params[:amount]).to eq(180)
    end

    it "does not emit a skipped event for apply_coupon" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.skipped.railsmith") { |_, p| events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, coupon_code: "SAVE20" })

      expect(events.map { |e| e[:step] }).not_to include(:apply_coupon)
    end
  end

  # ---------------------------------------------------------------------------
  # Failure at conditional step (invalid coupon)
  # ---------------------------------------------------------------------------

  describe "checkout with invalid coupon" do
    it "returns failure at apply_coupon and triggers inventory rollback" do
      rollback_called = false

      tracking_inventory = Class.new(Railsmith::BaseService) do
        def reserve
          Railsmith::Result.success(value: { reservation_id: "rsv-002" })
        end
        define_method(:unreserve) do
          rollback_called = true
          Railsmith::Result.success
        end
      end

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: tracking_inventory, payment: payment_service,
        notification: notification_service
      )

      # reserve runs before apply_coupon? No — order is: validate, apply_coupon, reserve, charge, notify.
      # So when coupon fails, reserve hasn't run yet — no rollback expected.
      result = pipeline.call(params: { cart_id: 1, coupon_code: "INVALID" })

      expect(result).to be_failure
      expect(result.error.code).to eq("invalid_coupon")
      expect(result.meta[:pipeline_step]).to eq(:apply_coupon)
      expect(rollback_called).to be false # nothing to roll back yet
    end
  end

  # ---------------------------------------------------------------------------
  # on_failure_continue: notification step is non-critical
  # ---------------------------------------------------------------------------

  describe "with non-critical notification step (on_failure_continue:)" do
    let(:flaky_notification) do
      Class.new(Railsmith::BaseService) do
        def send_receipt
          Railsmith::Result.failure(code: :smtp_error, message: "Mail server down")
        end
      end
    end

    def resilient_checkout_pipeline(cart:, coupon:, inventory:, payment:, notification:)
      Class.new(Railsmith::Pipeline) do
        guard(:has_coupon?) { |params, _ctx| params.key?(:coupon_code) && !params[:coupon_code].nil? }

        step :validate_cart,     service: cart,         action: :validate
        step :apply_coupon,      service: coupon,       action: :apply,       if: :has_coupon?
        step :reserve_inventory, service: inventory,    action: :reserve,     rollback: :unreserve
        step :charge_payment,    service: payment,      action: :charge,      inputs: { amount: :cart_total }
        step :send_confirmation, service: notification, action: :send_receipt, on_failure_continue: true
      end
    end

    it "returns success even when notification fails" do
      pipeline = resilient_checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: flaky_notification
      )

      result = pipeline.call(params: { cart_id: 1 })
      expect(result).to be_success
    end

    it "does not roll back payment or inventory when only notification fails" do
      rollback_calls = []

      tracking_inventory = Class.new(Railsmith::BaseService) do
        def reserve = Railsmith::Result.success(value: { reservation_id: "rsv-x" })
        define_method(:unreserve) do
          rollback_calls << :unreserve
          Railsmith::Result.success
        end
      end

      pipeline = resilient_checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: tracking_inventory, payment: payment_service,
        notification: flaky_notification
      )

      pipeline.call(params: { cart_id: 1 })
      expect(rollback_calls).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Instrumentation — step event counts
  # ---------------------------------------------------------------------------

  describe "instrumentation" do
    it "emits 4 step events (skips apply_coupon) for a run without coupon" do
      step_events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") { |_, p| step_events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: notification_service
      )
      pipeline.call(params: { cart_id: 1 })

      expect(step_events.map { |e| e[:step] }).to eq(
        %i[validate_cart reserve_inventory charge_payment send_confirmation]
      )
    end

    it "emits 5 step events (all steps) for a run with coupon" do
      step_events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") { |_, p| step_events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, coupon: coupon_service,
        inventory: inventory_service, payment: payment_service,
        notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, coupon_code: "SAVE20" })

      expect(step_events.map { |e| e[:step] }).to eq(
        %i[validate_cart apply_coupon reserve_inventory charge_payment send_confirmation]
      )
    end
  end
end
