require_relative "smswire/version"

# Smswire is the production SMS layer for Rails: messenger classes and
# templates, a provider-agnostic message object, persisted deliveries with
# status callbacks, consent and keyword handling, retries, development
# sandboxing, previews, and test helpers.
#
# This pre-release reserves the gem name. See docs/SPEC.md for the design.
module Smswire
  class Error < StandardError; end
end
