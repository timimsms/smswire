require "test_helper"

class SmswireTest < Minitest::Test
  def test_has_a_version_number
    refute_nil Smswire::VERSION
  end

  def test_version_is_a_prerelease
    assert Gem::Version.new(Smswire::VERSION).prerelease?
  end
end
