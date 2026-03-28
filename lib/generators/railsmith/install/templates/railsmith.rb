# frozen_string_literal: true

Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true
  config.strict_mode = false
  config.serializer_adapter = :auto
  # Approved context_domain → service_domain pairs, e.g.:
  # config.cross_domain_allowlist = [{ from: :billing, to: :catalog }]
  config.on_cross_domain_violation = nil # optional Proc, called on each violation when strict_mode is true
end
