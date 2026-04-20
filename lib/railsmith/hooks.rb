# frozen_string_literal: true

module Railsmith
  # Lifecycle hook infrastructure: before / after / around callbacks on service
  # actions, with conditional execution (+if:+/+unless:+), named hooks that can
  # be skipped by subclasses, and global hooks declared via +Railsmith.configure+.
  #
  # See {Railsmith::Hooks::Dsl} for the public class-level API, or +docs/hooks.md+
  # for a full guide with examples.
  module Hooks
  end
end

require_relative "hooks/errors"
require_relative "hooks/hook_entry"
require_relative "hooks/hook_chain"
require_relative "hooks/hook_registry"
require_relative "hooks/runner"
require_relative "hooks/dsl"
