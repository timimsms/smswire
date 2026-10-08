require "test_helper"

class QuietHoursTest < Smswire::TestCase
  NEW_YORK = ActiveSupport::TimeZone["America/New_York"]

  def resume(window, at, zone = NEW_YORK) = Smswire::QuietHours.resume_at(window, time_zone: zone, now: at)

  test "a window that wraps midnight" do
    window = "21:00".."08:00"
    assert_equal NEW_YORK.parse("2026-01-16 08:00"), resume(window, NEW_YORK.parse("2026-01-15 22:30"))
    assert_equal NEW_YORK.parse("2026-01-15 08:00"), resume(window, NEW_YORK.parse("2026-01-15 06:59"))
    assert_equal NEW_YORK.parse("2026-01-16 08:00"), resume(window, NEW_YORK.parse("2026-01-15 21:00"))
    assert_nil resume(window, NEW_YORK.parse("2026-01-15 08:00"))
    assert_nil resume(window, NEW_YORK.parse("2026-01-15 20:59"))
  end

  test "a same-day window" do
    window = "12:00".."13:30"
    assert_equal NEW_YORK.parse("2026-01-15 13:30"), resume(window, NEW_YORK.parse("2026-01-15 12:15"))
    assert_nil resume(window, NEW_YORK.parse("2026-01-15 13:30"))
  end

  test "the window is evaluated in the given zone" do
    utc_now = Time.utc(2026, 1, 15, 3) # 22:00 in New York, 19:00 in Los Angeles
    assert resume("21:00".."08:00", utc_now, NEW_YORK)
    assert_nil resume("21:00".."08:00", utc_now, ActiveSupport::TimeZone["America/Los_Angeles"])
  end

  test "resume time survives a daylight saving change" do
    assert_equal NEW_YORK.parse("2026-03-08 08:00"), resume("21:00".."08:00", NEW_YORK.parse("2026-03-07 23:00"))
  end

  test "invalid windows raise" do
    assert_raises(Smswire::ConfigurationError) { resume("21:00-08:00", Time.current) }
    assert_raises(Smswire::ConfigurationError) { resume("25:00".."08:00", Time.current) }
    assert_nil resume(nil, Time.current)
  end
end
