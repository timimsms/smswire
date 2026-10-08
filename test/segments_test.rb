require "test_helper"

class SegmentsTest < Smswire::TestCase
  def analyze(text) = Smswire::Segments.analyze(text)

  test "alphabet tables have the GSM 03.38 sizes" do
    assert_equal 127, Smswire::Segments::GSM_BASIC.size
    assert_equal 10, Smswire::Segments::GSM_EXTENDED.size
  end

  test "empty body has no segments" do
    assert_equal 0, analyze("").segments
    assert_equal 0, analyze(nil).segments
  end

  test "GSM-7 single and concatenated limits" do
    assert_equal [:gsm7, 160, 1], analyze("a" * 160).deconstruct
    assert_equal 2, analyze("a" * 161).segments
    assert_equal 2, analyze("a" * 306).segments
    assert_equal 3, analyze("a" * 307).segments
  end

  test "extension characters cost two units" do
    analysis = analyze("{" * 80)
    assert_equal 160, analysis.units
    assert_equal 1, analysis.segments
    assert analysis.gsm7?
  end

  test "extension characters are not split across segments" do
    body = ("a" * 152) + "€" + ("a" * 152)
    assert_equal 306, analyze(body).units
    assert_equal 3, analyze(body).segments
  end

  test "non-GSM characters switch to UCS-2 limits" do
    assert_equal :ucs2, analyze("Café ☕").encoding
    assert_equal 1, analyze("ж" * 70).segments
    assert_equal 2, analyze("ж" * 71).segments
    assert_equal 3, analyze("ж" * 135).segments
  end

  test "astral characters count as two UTF-16 units" do
    analysis = analyze("😀" * 35)
    assert_equal 70, analysis.units
    assert_equal 1, analysis.segments
    assert_equal "UCS-2", analysis.encoding_label
  end
end
