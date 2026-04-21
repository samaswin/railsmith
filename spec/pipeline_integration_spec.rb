# frozen_string_literal: true

require "spec_helper"

# End-to-end pipeline scenarios modelled after a real checkout flow.
# Each "service" is a minimal stub that captures calls and returns controlled
# results so we can verify the full pipeline contract without a database.
RSpec.describe "Pipeline integration — CheckoutPipeline" do
  after { Railsmith::Instrumentation.reset! }

  # ---------------------------------------------------------------------------
  # Domain stub services
  # ---------------------------------------------------------------------------

  let(:cart_service) do
    Class.new(Railsmith::BaseService) do
      def validate
        return Railsmith::Result.failure(code: :validation_error, message: "Cart is empty") if params[:cart_id].nil?

        Railsmith::Result.success(value: { cart_total: 150, item_count: 3 })
      end
    end
  end

  let(:inventory_service) do
    Class.new(Railsmith::BaseService) do
      def reserve
        return Railsmith::Result.failure(code: :conflict, message: "Out of stock") if params[:out_of_stock]

        Railsmith::Result.success(value: { reservation_id: "rsv-001" })
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
  # Pipeline under test
  # ---------------------------------------------------------------------------

  # Defined fresh in each example so service stubs can be injected.
  # In real usage this would be a named class: class CheckoutPipeline < Railsmith::Pipeline
  def checkout_pipeline(cart:, inventory:, payment:, notification:)
    _cart = cart
    _inv  = inventory
    _pay  = payment
    _notif = notification

    Class.new(Railsmith::Pipeline) do
      step :validate_cart,     service: _cart,  action: :validate
      step :reserve_inventory, service: _inv,   action: :reserve
      # inputs: renames :cart_total → :amount for the payment step
      step :charge_payment,    service: _pay,   action: :charge,     inputs: { amount: :cart_total }
      step :send_confirmation, service: _notif, action: :send_receipt
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "happy path" do
    it "returns a success Result" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 42, user_id: 7 })
      expect(result).to be_success
    end

    it "returns the last step's result value" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 42, user_id: 7 })
      expect(result.value).to include(email_sent: true)
    end

    it "correctly renames :cart_total to :amount for the payment step" do
      received_params = nil
      capturing_payment = Class.new(Railsmith::BaseService) do
        define_method(:charge) do
          received_params = params
          Railsmith::Result.success(value: { payment_id: "pay-x" })
        end
      end

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: capturing_payment, notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, user_id: 2 })

      expect(received_params).to include(amount: 150)
      expect(received_params).not_to have_key(:cart_total)
    end
  end

  # ---------------------------------------------------------------------------
  # Failure paths
  # ---------------------------------------------------------------------------

  describe "failure at validate_cart" do
    it "returns a failure with pipeline_step: :validate_cart" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { user_id: 7 })  # cart_id: nil → failure

      expect(result).to be_failure
      expect(result.error.code).to    eq("validation_error")
      expect(result.meta[:pipeline_step]).to eq(:validate_cart)
    end

    it "does not invoke subsequent steps" do
      calls = []
      tracking_inv = Class.new(Railsmith::BaseService) do
        define_method(:reserve) do
          calls << :reserve
          Railsmith::Result.success
        end
      end

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: tracking_inv,
        payment: payment_service, notification: notification_service
      )
      pipeline.call(params: {})  # no cart_id

      expect(calls).to be_empty
    end
  end

  describe "failure at reserve_inventory" do
    it "returns a failure with pipeline_step: :reserve_inventory" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, out_of_stock: true })

      expect(result).to be_failure
      expect(result.meta[:pipeline_step]).to eq(:reserve_inventory)
    end
  end

  describe "failure at charge_payment" do
    it "returns a failure with pipeline_step: :charge_payment" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      result = pipeline.call(params: { cart_id: 1, decline: true })

      expect(result).to be_failure
      expect(result.error.message).to eq("Card declined")
      expect(result.meta[:pipeline_step]).to eq(:charge_payment)
    end
  end

  # ---------------------------------------------------------------------------
  # call! interface
  # ---------------------------------------------------------------------------

  describe ".call!" do
    it "raises Railsmith::Failure with the wrapped result on failure" do
      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )

      expect {
        pipeline.call!(params: {})  # no cart_id
      }.to raise_error(Railsmith::Failure) do |ex|
        expect(ex.result.meta[:pipeline_step]).to eq(:validate_cart)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Instrumentation
  # ---------------------------------------------------------------------------

  describe "instrumentation" do
    it "emits 4 step events and 1 pipeline event for a full successful run" do
      step_events     = []
      pipeline_events = []

      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith")    { |_, p| step_events     << p }
      Railsmith::Instrumentation.subscribe("pipeline.railsmith")         { |_, p| pipeline_events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, user_id: 2 })

      expect(step_events.size).to eq(4)
      expect(step_events.map { |e| e[:step] }).to eq(
        %i[validate_cart reserve_inventory charge_payment send_confirmation]
      )
      expect(pipeline_events.size).to eq(1)
      expect(pipeline_events.first[:status]).to eq(:success)
    end

    it "emits only steps up to the failure, plus the pipeline event" do
      step_events     = []
      pipeline_events = []

      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith")    { |_, p| step_events     << p }
      Railsmith::Instrumentation.subscribe("pipeline.railsmith")         { |_, p| pipeline_events << p }

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: payment_service, notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, out_of_stock: true })

      expect(step_events.map { |e| e[:step] }).to eq(%i[validate_cart reserve_inventory])
      expect(pipeline_events.first[:status]).to eq(:failure)
    end
  end

  # ---------------------------------------------------------------------------
  # Param accumulation across all steps
  # ---------------------------------------------------------------------------

  describe "accumulated params" do
    it "makes every prior step's result.value available to later steps" do
      # After validate_cart: accumulated has cart_total, item_count
      # After reserve_inventory: accumulated also has reservation_id
      # charge_payment receives amount (renamed from cart_total) + reservation_id + others

      received_by_payment = nil
      capturing_payment = Class.new(Railsmith::BaseService) do
        define_method(:charge) do
          received_by_payment = params
          Railsmith::Result.success(value: { payment_id: "pay-x" })
        end
      end

      pipeline = checkout_pipeline(
        cart: cart_service, inventory: inventory_service,
        payment: capturing_payment, notification: notification_service
      )
      pipeline.call(params: { cart_id: 1, user_id: 2 })

      # :cart_total was renamed to :amount by inputs:, but :reservation_id comes through
      expect(received_by_payment).to include(
        amount:         150,
        item_count:     3,
        reservation_id: "rsv-001",
        user_id:        2
      )
    end
  end
end
