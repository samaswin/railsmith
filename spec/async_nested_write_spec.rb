# frozen_string_literal: true

require "spec_helper"

# A fake ActiveJob-like class that records every `perform_later` call so we
# can assert on enqueueing without pulling in the real ActiveJob runtime.
class FakeRailsmithAsyncJob
  class << self
    attr_accessor :jobs

    def perform_later(**payload)
      @jobs ||= []
      job_id = "job-#{@jobs.size + 1}"
      @jobs << { payload: payload, job_id: job_id }
      FakeJobHandle.new(job_id)
    end

    def reset!
      @jobs = []
    end
  end

  FakeJobHandle = Struct.new(:job_id)
end

RSpec.describe "Railsmith::BaseService async nested writes" do
  before(:all) do
    require "active_record"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :anw_orders, force: true do |t|
        t.decimal :total, precision: 10, scale: 2
        t.timestamps null: false
      end

      create_table :anw_audits, force: true do |t|
        t.integer :anw_order_id
        t.string  :kind
        t.timestamps null: false
      end
    end

    Object.const_set(:AnwOrder,  Class.new(ActiveRecord::Base) { self.table_name = "anw_orders" })
    Object.const_set(:AnwAudit,  Class.new(ActiveRecord::Base) { self.table_name = "anw_audits" })
  end

  after(:all) do
    %i[AnwOrder AnwAudit].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
  end

  before do
    AnwOrder.delete_all
    AnwAudit.delete_all
    FakeRailsmithAsyncJob.reset!
  end

  around do |ex|
    previous = Railsmith.configuration.async_job_class
    ex.run
    Railsmith.configuration.async_job_class = previous
  end

  let(:audit_service) do
    # Give the service a stable name so AsyncNestedWriteJob can reconstitute it
    # from service_class.name.
    unless Object.const_defined?(:AnwAuditService)
      Object.const_set(
        :AnwAuditService,
        Class.new(Railsmith::BaseService) { model AnwAudit }
      )
    end
    AnwAuditService
  end

  def build_order_service(audit_svc, async: true)
    Class.new(Railsmith::BaseService) do
      model AnwOrder
      has_many :anw_audits, service: audit_svc, async: async
    end
  end

  # ---------------------------------------------------------------------------
  # Create path
  # ---------------------------------------------------------------------------

  describe "create with async: true has_many" do
    before { Railsmith.configuration.async_job_class = FakeRailsmithAsyncJob }

    it "enqueues a job instead of writing nested records inline" do
      svc = build_order_service(audit_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 50.00 },
          anw_audits: [
            { attributes: { kind: "viewed" } },
            { attributes: { kind: "clicked" } }
          ]
        },
        context: {}
      )

      expect(result).to be_success
      expect(AnwOrder.count).to eq(1)
      # Children are NOT written inline.
      expect(AnwAudit.count).to eq(0)
      # A job WAS enqueued with the nested payload.
      expect(FakeRailsmithAsyncJob.jobs.size).to eq(1)
      payload = FakeRailsmithAsyncJob.jobs.first[:payload]
      expect(payload[:association]).to eq("anw_audits")
      expect(payload[:parent_id]).to eq(AnwOrder.first.id)
      expect(payload[:nested_params]).to eq([
                                              { attributes: { kind: "viewed" } },
                                              { attributes: { kind: "clicked" } }
                                            ])
      expect(payload[:mode]).to eq("create")
      expect(payload[:service_class]).to eq(audit_service.name)
    end

    it "propagates the request context (including request_id) into the job payload" do
      svc = build_order_service(audit_service)

      svc.call(
        action: :create,
        params: {
          attributes: { total: 10.00 },
          anw_audits: [{ attributes: { kind: "viewed" } }]
        },
        context: { current_domain: :commerce, request_id: "req-xyz", actor_id: 99 }
      )

      ctx = FakeRailsmithAsyncJob.jobs.first[:payload][:context]
      expect(ctx[:request_id]).to eq("req-xyz")
      expect(ctx[:actor_id]).to eq(99)
      expect(ctx[:current_domain]).to eq(:commerce)
    end

    it "returns meta flagging the write as async with the job id" do
      svc = build_order_service(audit_service)

      result = svc.call(
        action: :create,
        params: {
          attributes: { total: 1.00 },
          anw_audits: [{ attributes: { kind: "viewed" } }]
        },
        context: {}
      )

      audit_meta = result.meta.dig(:nested, :anw_audits)
      expect(audit_meta).to include(async: true, association: :anw_audits)
      expect(audit_meta[:job_id]).to eq("job-1")
    end

    it "emits a nested_write.enqueued.railsmith event" do
      captured = []
      Railsmith::Instrumentation.subscribe("nested_write.enqueued") do |_, payload|
        captured << payload
      end

      svc = build_order_service(audit_service)
      svc.call(
        action: :create,
        params: {
          attributes: { total: 1.00 },
          anw_audits: [{ attributes: { kind: "viewed" } }]
        },
        context: {}
      )

      expect(captured.size).to eq(1)
      expect(captured.first).to include(association: :anw_audits, service: audit_service.name)
      Railsmith::Instrumentation.reset!
    end

    it "raises AsyncNotConfiguredError when no async_job_class is configured" do
      Railsmith.configuration.async_job_class = nil
      svc = build_order_service(audit_service)

      expect do
        svc.call(
          action: :create,
          params: {
            attributes: { total: 1.00 },
            anw_audits: [{ attributes: { kind: "viewed" } }]
          },
          context: {}
        )
      end.to raise_error(Railsmith::AsyncNotConfiguredError, /async_job_class/)
    end
  end

  # ---------------------------------------------------------------------------
  # Update path
  # ---------------------------------------------------------------------------

  describe "update with async: true has_many" do
    before { Railsmith.configuration.async_job_class = FakeRailsmithAsyncJob }

    it "enqueues a job on update, propagating mode: :update" do
      svc = build_order_service(audit_service)
      order = AnwOrder.create!(total: 10.00)

      svc.call(
        action: :update,
        params: {
          id: order.id,
          attributes: { total: 12.00 },
          anw_audits: [{ attributes: { kind: "updated" } }]
        },
        context: {}
      )

      expect(AnwAudit.count).to eq(0)
      expect(FakeRailsmithAsyncJob.jobs.size).to eq(1)
      payload = FakeRailsmithAsyncJob.jobs.first[:payload]
      expect(payload[:mode]).to eq("update")
      expect(payload[:parent_id]).to eq(order.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Job re-entry — perform_nested_write_for_job writes inline
  # ---------------------------------------------------------------------------

  describe "#perform_nested_write_for_job" do
    before { Railsmith.configuration.async_job_class = FakeRailsmithAsyncJob }

    it "re-runs the nested write inline when invoked by the job" do
      svc_class = build_order_service(audit_service)
      order = AnwOrder.create!(total: 1.00)

      svc = svc_class.new(params: {}, context: Railsmith::Context.new)
      result = svc.send(
        :perform_nested_write_for_job,
        :anw_audits,
        order,
        [{ attributes: { kind: "replayed" } }],
        :create
      )

      expect(result).to be_success
      expect(AnwAudit.count).to eq(1)
      expect(AnwAudit.first.anw_order_id).to eq(order.id)
    end

    it "raises ArgumentError for an unknown association" do
      svc_class = build_order_service(audit_service)
      order = AnwOrder.create!(total: 1.00)
      svc = svc_class.new(params: {}, context: Railsmith::Context.new)

      expect do
        svc.send(:perform_nested_write_for_job, :missing, order, [], :create)
      end.to raise_error(ArgumentError, /unknown association/)
    end
  end
end
