require "test_helper"

# Keeps the README, spec, and guides in step with the code: every
# Smswire.configure setting and every Smswire constant they name must exist.
class DocumentationTest < Smswire::TestCase
  ROOT = File.expand_path("..", __dir__)
  DOCS = [File.join(ROOT, "README.md"), *Dir[File.join(ROOT, "docs/guides/*.md")]].freeze

  # Options set inside Noticed `deliver_by` blocks, not on Smswire.config.
  NOTICED_OPTIONS = %w[messenger action args kwargs params sms_queue sms_priority json error_handler credentials
    wait wait_until queue priority if unless].freeze

  def ruby_snippets(path)
    File.read(path).scan(/```ruby\n(.*?)```/m).flatten
  end

  test "documented settings exist" do
    DOCS.each do |path|
      ruby_snippets(path).each do |snippet|
        snippet.scan(/\bconfig\.([a-z_]+)\s*=(?!=)/).flatten.uniq.each do |setting|
          next if NOTICED_OPTIONS.include?(setting)

          assert_respond_to Smswire.config, :"#{setting}=", "#{File.basename(path)} documents config.#{setting}"
        end
      end
    end
  end

  test "documented Smswire constants exist" do
    (DOCS + [File.join(ROOT, "docs/SPEC.md")]).each do |path|
      File.read(path).scan(/\bSmswire::[A-Z][A-Za-z]*(?:::[A-Z][A-Za-z]*)*/).uniq.each do |name|
        next if name.start_with?("Smswire::Acme") # example adapter gem in the provider guide

        assert Object.const_defined?(name), "#{File.basename(path)} mentions #{name}"
      end
    end
  end

  test "documented generators exist" do
    DOCS.each do |path|
      File.read(path).scan(/generate (smswire:[a-z_]+)/).flatten.uniq.each do |generator|
        file = File.join(ROOT, "lib/generators/smswire", generator.delete_prefix("smswire:"))
        assert Dir.exist?(file), "#{File.basename(path)} mentions #{generator}"
      end
    end
  end
end
