# frozen_string_literal: true

require "spec_helper"

FakeRailsmithController = Class.new do
  @rescue_handlers = []

  def self.rescue_from(exception_class, &block)
    @rescue_handlers << [exception_class, block]
  end

  class << self
    attr_reader :rescue_handlers
  end

  include Railsmith::ControllerHelpers

  def dispatch(exception)
    handler = self.class.rescue_handlers.find { |klass, _| exception.is_a?(klass) }
    instance_exec(exception, &handler[1]) if handler
  end

  attr_reader :rendered

  def render(json:, status:)
    @rendered = { json:, status: }
  end
end

RSpec.describe Railsmith::ControllerHelpers do
  # ---------------------------------------------------------------------------
  # Minimal fake controller that supports rescue_from / render without Rails.
  # Including ControllerHelpers triggers the `included do` block, which calls
  # rescue_from on the host class. We implement just enough of that interface
  # to exercise every line in controller_helpers.rb.
  # ---------------------------------------------------------------------------
  def build_controller_class
    FakeRailsmithController
  end

  # ---------------------------------------------------------------------------
  # 1. ERROR_STATUS_MAP constant
  # ---------------------------------------------------------------------------

  describe "ERROR_STATUS_MAP" do
    subject(:map) { described_class::ERROR_STATUS_MAP }

    it { is_expected.to be_frozen }

    it "maps every documented error code" do
      expect(map).to eq(
        "validation_error" => :unprocessable_entity,
        "not_found" => :not_found,
        "conflict" => :conflict,
        "unauthorized" => :unauthorized,
        "unexpected" => :internal_server_error
      )
    end
  end

  # ---------------------------------------------------------------------------
  # 2. included do — rescue_from registration
  # ---------------------------------------------------------------------------

  describe "included hook" do
    it "registers a rescue_from handler for Railsmith::Failure when included" do
      klass = build_controller_class
      handler_classes = klass.rescue_handlers.map(&:first)
      expect(handler_classes).to include(Railsmith::Failure)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Rescue handler body — render + status resolution
  # ---------------------------------------------------------------------------

  describe "rescue handler" do
    subject(:controller) { build_controller_class.new }

    def raise_failure(error)
      result    = Railsmith::Result.failure(error:)
      exception = Railsmith::Failure.new(result)
      controller.dispatch(exception)
      controller.rendered
    end

    it "renders JSON with the failure result payload" do
      rendered = raise_failure(Railsmith::Errors.validation_error(message: "bad input"))
      expect(rendered[:json]).to include(success: false)
      expect(rendered[:json][:error][:code]).to eq("validation_error")
    end

    it "returns :unprocessable_entity for validation_error" do
      rendered = raise_failure(Railsmith::Errors.validation_error)
      expect(rendered[:status]).to eq(:unprocessable_entity)
    end

    it "returns :not_found for not_found" do
      rendered = raise_failure(Railsmith::Errors.not_found)
      expect(rendered[:status]).to eq(:not_found)
    end

    it "returns :conflict for conflict" do
      rendered = raise_failure(Railsmith::Errors.conflict)
      expect(rendered[:status]).to eq(:conflict)
    end

    it "returns :unauthorized for unauthorized" do
      rendered = raise_failure(Railsmith::Errors.unauthorized)
      expect(rendered[:status]).to eq(:unauthorized)
    end

    it "returns :internal_server_error for unexpected" do
      rendered = raise_failure(Railsmith::Errors.unexpected)
      expect(rendered[:status]).to eq(:internal_server_error)
    end

    it "defaults to :internal_server_error for unknown error codes" do
      custom_error = Railsmith::Errors::ErrorPayload.new(
        code: "some_custom_code", message: "custom", details: {}
      )
      rendered = raise_failure(custom_error)
      expect(rendered[:status]).to eq(:internal_server_error)
    end

    it "includes the error details in the rendered JSON" do
      error = Railsmith::Errors.validation_error(message: "Name blank", details: { name: ["can't be blank"] })
      rendered = raise_failure(error)
      expect(rendered[:json][:error][:details]).to eq({ name: ["can't be blank"] })
    end

    it "includes meta in the rendered JSON" do
      rendered = raise_failure(Railsmith::Errors.not_found)
      expect(rendered[:json]).to have_key(:meta)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. railsmith_context helper — request_id propagation
  # ---------------------------------------------------------------------------

  describe "#railsmith_context" do
    # Minimal fake ActionDispatch::Request double — just the method we read.
    let(:fake_request) do
      Struct.new(:request_id).new("inbound-abc-123")
    end

    let(:controller_class) do
      klass = Class.new do
        @rescue_handlers = []
        def self.rescue_from(exception_class, &block)
          @rescue_handlers << [exception_class, block]
        end
        class << self
          attr_reader :rescue_handlers
        end
        include Railsmith::ControllerHelpers

        attr_accessor :request

        def current_user
          Struct.new(:id).new(123)
        end
      end
      klass
    end

    it "returns a Railsmith::Context" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      expect(ctrl.railsmith_context).to be_a(Railsmith::Context)
    end

    it "copies request.request_id onto the Context" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      expect(ctrl.railsmith_context.request_id).to eq("inbound-abc-123")
    end

    it "passes through an explicit domain:" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      expect(ctrl.railsmith_context(domain: :commerce).domain).to eq(:commerce)
    end

    it "passes through arbitrary extras onto the Context" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      ctx = ctrl.railsmith_context(domain: :commerce, actor_id: 42, tenant_id: 7)
      expect(ctx[:actor_id]).to eq(42)
      expect(ctx[:tenant_id]).to eq(7)
      expect(ctx.request_id).to eq("inbound-abc-123")
    end

    it "seeds actor_id from current_user when available" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      ctx = ctrl.railsmith_context(domain: :commerce)
      expect(ctx[:actor_id]).to eq(123)
    end

    it "seeds actor from current_user when available" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      ctx = ctrl.railsmith_context(domain: :commerce)
      expect(ctx[:actor]).to be_a(Struct)
      expect(ctx[:actor].id).to eq(123)
      expect(ctx.to_h).not_to have_key(:actor)
    end

    it "does not override an explicit actor_id:" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      ctx = ctrl.railsmith_context(domain: :commerce, actor_id: 999)
      expect(ctx[:actor_id]).to eq(999)
    end

    it "does not override an explicit actor:" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      custom_actor = Struct.new(:id).new(555)
      ctx = ctrl.railsmith_context(domain: :commerce, actor: custom_actor)
      expect(ctx[:actor].id).to eq(555)
      expect(ctx.to_h).not_to have_key(:actor)
    end

    it "honors an explicit request_id passed in extras" do
      ctrl = controller_class.new
      ctrl.request = fake_request
      ctx = ctrl.railsmith_context(request_id: "caller-override")
      expect(ctx.request_id).to eq("caller-override")
    end

    it "auto-generates a request_id when no request is available" do
      # Controller that does not respond to #request at all.
      ctrl = Class.new do
        include Railsmith::ControllerHelpers
      end.new
      expect(ctrl.railsmith_context.request_id).to match(/\A[0-9a-f-]{36}\z/)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Module structure
  # ---------------------------------------------------------------------------

  describe "module structure" do
    it "is a module" do
      expect(described_class).to be_a(Module)
    end

    it "defines ERROR_STATUS_MAP" do
      expect(described_class.const_defined?(:ERROR_STATUS_MAP)).to be true
    end
  end
end
