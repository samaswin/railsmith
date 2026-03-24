# frozen_string_literal: true

Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true
  config.strict_mode = false
  config.serializer_adapter = :auto
end
