# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Railsmith::ControllerHelpers end-to-end rescue_from" do
  before do
    require "action_controller"
    require "action_dispatch"
    require "rack/mock"
  end

  it "rescues Railsmith::Failure and renders JSON with the mapped status" do
    route_set = ActionDispatch::Routing::RouteSet.new

    controller_class = Class.new(ActionController::Base) do
      include Railsmith::ControllerHelpers

      def index
        result = Railsmith::Result.failure(error: Railsmith::Errors.not_found(message: "missing"))
        raise Railsmith::Failure, result
      end
    end

    controller_const_name = "RailsmithEndToEndController"
    Object.const_set(controller_const_name, controller_class)

    begin
      route_set.draw do
        get "/railsmith_e2e" => "railsmith_end_to_end#index"
      end

      env = Rack::MockRequest.env_for("/railsmith_e2e", "REQUEST_METHOD" => "GET")
      status, headers, body = route_set.call(env)

      expect(status).to eq(404)
      expect(headers["Content-Type"]).to include("application/json")
      payload = +""
      body.each { |chunk| payload << chunk.to_s }
      json = JSON.parse(payload)
      expect(json.dig("error", "code")).to eq("not_found")
    ensure
      Object.send(:remove_const, controller_const_name) if Object.const_defined?(controller_const_name)
    end
  end
end
