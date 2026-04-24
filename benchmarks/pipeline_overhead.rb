# frozen_string_literal: true

# Compare sequential BaseService.call vs Railsmith::Pipeline for the same steps.
# Run from gem root: ruby benchmarks/pipeline_overhead.rb
#
# This is a coarse micro-benchmark (warmup + monotonic clock); use it to spot
# large regressions, not as a substitute for production profiling.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "railsmith"

ITERATIONS = 50_000
WARMUP     = 1_000

StepSvc = Class.new(Railsmith::BaseService) do
  define_method(:go) { Railsmith::Result.success(value: { n: 1 }) }
end

SequentialPipeline = Class.new(Railsmith::Pipeline) do
  step :a, service: StepSvc, action: :go
  step :b, service: StepSvc, action: :go
  step :c, service: StepSvc, action: :go
end

def ms(&block)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  block.call
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
end

ctx = Railsmith::Context.build(nil)
params = { seed: 1 }

WARMUP.times { StepSvc.call(action: :go, params: params, context: ctx) }
WARMUP.times { SequentialPipeline.call(params: params, context: ctx) }

raw_seq = ms do
  ITERATIONS.times do
    r = params
    r = StepSvc.call(action: :go, params: r, context: ctx).value.merge(r)
    r = StepSvc.call(action: :go, params: r, context: ctx).value.merge(r)
    StepSvc.call(action: :go, params: r, context: ctx)
  end
end

raw_pipe = ms { ITERATIONS.times { SequentialPipeline.call(params: params, context: ctx) } }

overhead_pct = ((raw_pipe / raw_seq) - 1.0) * 100.0

puts "Iterations: #{ITERATIONS}"
puts format("Sequential (3× service.call merge): %8.1f ms", raw_seq * 1000)
puts format("Pipeline (3 steps):               %8.1f ms", raw_pipe * 1000)
puts format("Pipeline overhead vs sequential:   %+6.2f %%", overhead_pct)
