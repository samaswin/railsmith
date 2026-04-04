# frozen_string_literal: true

require_relative "cross_domain_warning_formatter"

module Railsmith
  # Detects when a service from one bounded context runs under another domain's
  # request context (+context[:current_domain]+). Emits non-blocking
  # +cross_domain.warning.railsmith+ instrumentation by default; optional strict
  # hook runs when +strict_mode+ is enabled.
  module CrossDomainGuard
    def self.emit_if_violation(instance:, action:, configuration: Railsmith.configuration)
      return unless configuration.warn_on_cross_domain_calls

      mismatch = domain_mismatch(instance)
      return if mismatch.nil? || allowlisted?(configuration, mismatch)

      publish_violation(instance:, action:, configuration:, mismatch:)
    end

    def self.allowlisted?(configuration, mismatch)
      allowed_crossing?(
        configuration.cross_domain_allowlist,
        mismatch[:context_domain],
        mismatch[:service_domain]
      )
    end

    def self.publish_violation(instance:, action:, configuration:, mismatch:)
      base = build_payload(
        context_domain: mismatch[:context_domain],
        service_domain: mismatch[:service_domain],
        service: instance.class.name,
        action: action,
        strict_mode: configuration.strict_mode
      )
      payload = instrument_payload(base)

      Instrumentation.instrument("cross_domain.warning", payload)
      configuration.on_cross_domain_violation&.call(payload) if configuration.strict_mode
    end

    def self.instrument_payload(base)
      base.merge(
        log_json_line: CrossDomainWarningFormatter.as_json_line(base),
        log_kv_line: CrossDomainWarningFormatter.as_key_value_line(base)
      )
    end

    def self.domain_mismatch(instance)
      context_domain = Context.normalize_current_domain(instance.context[:current_domain])
      service_domain = instance.class.domain
      return nil if context_domain.nil? || service_domain.nil?
      return nil if context_domain == service_domain

      { context_domain: context_domain, service_domain: service_domain }
    end

    def self.allowed_crossing?(allowlist, from_domain, to_domain)
      Array(allowlist).any? { |entry| pair_matches?(entry, from_domain, to_domain) }
    end

    def self.pair_matches?(entry, from_domain, to_domain)
      case entry
      when Hash
        hash_pair_matches?(entry, from_domain, to_domain)
      when Array
        array_pair_matches?(entry, from_domain, to_domain)
      else
        false
      end
    end

    def self.hash_pair_matches?(entry, from_domain, to_domain)
      from_key = entry[:from] || entry["from"]
      to_key = entry[:to] || entry["to"]
      Context.normalize_current_domain(from_key) == from_domain &&
        Context.normalize_current_domain(to_key) == to_domain
    end

    def self.array_pair_matches?(entry, from_domain, to_domain)
      return false unless entry.size == 2

      Context.normalize_current_domain(entry[0]) == from_domain &&
        Context.normalize_current_domain(entry[1]) == to_domain
    end

    def self.build_payload(context_domain:, service_domain:, service:, action:, strict_mode:)
      {
        event: "cross_domain.warning",
        context_domain: context_domain,
        service_domain: service_domain,
        service: service,
        action: action,
        strict_mode: strict_mode,
        blocking: false,
        occurred_at: Time.now.utc.iso8601(6)
      }
    end
  end
end
