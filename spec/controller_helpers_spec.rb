# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::ControllerHelpers do
  # ---------------------------------------------------------------------------
  # Minimal fake controller that supports rescue_from / render without Rails.
  # Including ControllerHelpers triggers the `included do` block, which calls
  # rescue_from on the host class. We implement just enough of that interface
  # to exercise every line in controller_helpers.rb.
  # ---------------------------------------------------------------------------
  def build_controller_class # rubocop:disable Metrics/MethodLength
    Class.new do
      @rescue_handlers = []

      def self.rescue_from(exception_class, &block)
        @rescue_handlers << [exception_class, block]
      end

      class << self
        attr_reader :rescue_handlers
      end

      include Railsmith::ControllerHelpers

      # Simulate the Rails rescue dispatch: find a matching handler and call it.
      def dispatch(exception)
        handler = self.class.rescue_handlers.find { |klass, _| exception.is_a?(klass) }
        instance_exec(exception, &handler[1]) if handler
      end

      attr_reader :rendered

      def render(json:, status:)
        @rendered = { json:, status: }
      end
    end
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
  # 4. Module structure
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
