require_relative "lib/smswire/version"

Gem::Specification.new do |spec|
  spec.name = "smswire"
  spec.version = Smswire::VERSION
  spec.authors = ["Tim Walsh"]
  spec.email = ["tim@mims.ms"]

  spec.summary = "The production SMS layer for Rails."
  spec.description = <<~DESC.strip
    Smswire gives Rails applications Action Mailer-style messenger classes and
    templates for SMS, a provider-agnostic message object, persisted deliveries
    with provider status callbacks, consent and keyword handling, quiet hours,
    retries, development sandboxing, previews, and test helpers. It complements
    Noticed with a delivery adapter and works standalone.
  DESC
  spec.homepage = "https://smswire.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/timimsms/smswire"
  spec.metadata["changelog_uri"] = "https://github.com/timimsms/smswire/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/timimsms/smswire/issues"
  spec.metadata["documentation_uri"] = "https://github.com/timimsms/smswire/blob/main/docs/SPEC.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?("test/", "bin/", ".github/", ".gitignore")
    end
  end
  spec.require_paths = ["lib"]

  # Runtime dependencies arrive with the first functional release (Phase 1
  # of docs/SPEC.md): activesupport, activejob, activerecord, actionview,
  # railties, all >= 7.1. This pre-release only reserves the name.
end
