require "test_helper"

class DeliveryJobTest < Smswire::TestCase
  test "deliver_later enqueues the action and runs it when performed" do
    delivery = OrderMessenger.with(order_number: "R9").delivery_window("+14155552671", window: "noon")
    assert_enqueued_with(job: Smswire::DeliveryJob, queue: "default") { delivery.deliver_later }
    assert_empty sms_deliveries

    perform_enqueued_jobs
    assert_equal ["Order R9 arrives noon"], sms_deliveries.map(&:body)
  end

  test "deliver_later honors queue, wait, and the configured default queue" do
    with_config(deliver_later_queue: :sms) do
      assert_enqueued_with(job: Smswire::DeliveryJob, queue: "sms") do
        OrderMessenger.literal("+14155552671", "hi").deliver_later
      end
    end
    travel_to Time.utc(2026, 1, 1, 12) do
      assert_enqueued_with(job: Smswire::DeliveryJob, queue: "urgent", at: 5.minutes.from_now) do
        OrderMessenger.literal("+14155552671", "hi").deliver_later(queue: :urgent, wait: 5.minutes)
      end
    end
  end

  test "deliver_later after reading the message raises" do
    delivery = OrderMessenger.literal("+14155552671", "hi")
    delivery.body
    assert_raises(Smswire::Error) { delivery.deliver_later }
  end

  test "transient errors are retried with backoff" do
    Smswire::Providers::Test.fail_next(Smswire::TransientError.new("timeout"))
    OrderMessenger.literal("+14155552671", "hi").deliver_later

    travel_to Time.utc(2026, 1, 1, 12) do
      perform_enqueued_jobs(only: Smswire::DeliveryJob) # first attempt fails, retry enqueued
      retry_job = enqueued_jobs.last
      assert_equal "Smswire::DeliveryJob", retry_job[:job].name
      assert_in_delta 3.seconds.from_now.to_f, retry_job[:at], 1
    end

    perform_enqueued_jobs
    assert_equal 1, sms_deliveries.size
  end

  test "throttled errors wait for retry_after" do
    Smswire::Providers::Test.fail_next(Smswire::ThrottledError.new("slow down", retry_after: 30))
    OrderMessenger.literal("+14155552671", "hi").deliver_later

    travel_to Time.utc(2026, 1, 1, 12) do
      perform_enqueued_jobs(only: Smswire::DeliveryJob)
      assert_in_delta 30.seconds.from_now.to_f, enqueued_jobs.last[:at], 1
    end
  end

  test "transient errors raise after the configured attempts" do
    with_config(retry_attempts: 2) do
      2.times { Smswire::Providers::Test.fail_next(Smswire::TransientError.new("down")) }
      OrderMessenger.literal("+14155552671", "hi").deliver_later
      assert_raises(Smswire::TransientError) do
        perform_enqueued_jobs(only: Smswire::DeliveryJob)
        perform_enqueued_jobs(only: Smswire::DeliveryJob)
      end
    end
    assert_empty sms_deliveries
  end

  test "permanent errors are not retried" do
    Smswire::Providers::Test.fail_next(Smswire::PermanentError.new("invalid", reason: :invalid_number))
    OrderMessenger.literal("+14155552671", "hi").deliver_later
    perform_enqueued_jobs
    assert_empty enqueued_jobs
    assert_empty sms_deliveries
  end
end
