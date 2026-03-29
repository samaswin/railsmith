# frozen_string_literal: true

require "json"

module Railsmith
  # Stable, log- and CI-friendly renderings of cross-domain warning payloads.
  module CrossDomainWarningFormatter
    module_function

    CANONICAL_KEYS = %i[
      event
      context_domain
      service_domain
      service
      action
      strict_mode
      blocking
      occurred_at
    ].freeze

    # Single-line JSON with sorted keys for grep and log aggregation.
    def as_json_line(payload)
      JSON.generate(ordered_hash(payload))
    end

    def ordered_hash(payload)
      ordered = CANONICAL_KEYS.each_with_object({}) do |key, acc|
        value = payload[key]
        acc[key.to_s] = json_scalar(value) unless value.nil?
      end
      payload.each do |key, value|
        string_key = key.to_s
        ordered[string_key] = json_scalar(value) unless ordered.key?(string_key) || value.nil?
      end
      ordered
    end

    # Space-separated key=value for quick human scanning (values are JSON-encoded).
    def as_key_value_line(payload)
      (canonical_kv_parts(payload) + extra_kv_parts(payload)).join(" ")
    end

    def canonical_kv_parts(payload)
      CANONICAL_KEYS.filter_map do |key|
        next if payload[key].nil?

        %(#{key}=#{JSON.generate(json_scalar(payload[key]))})
      end
    end

    def extra_kv_parts(payload)
      (payload.keys - CANONICAL_KEYS).sort.filter_map do |key|
        value = payload[key]
        next if value.nil?

        %(#{key}=#{JSON.generate(json_scalar(value))})
      end
    end

    def json_scalar(value)
      value.is_a?(Symbol) ? value.to_s : value
    end
  end
end
