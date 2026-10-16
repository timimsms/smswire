module Smswire
  # One outbound SMS, from claim through provider status callbacks.
  #
  # Status lifecycle: pending, then queued / accepted / sent from the
  # provider, then delivered, undelivered, or failed, and optionally read.
  # suppressed means an interceptor cancelled it. Status only moves forward,
  # so out-of-order callbacks are ignored.
  class Delivery < ApplicationRecord
    STATUSES = %w[pending suppressed queued accepted sent delivered undelivered failed read].freeze
    PROGRESS = {
      "pending" => 0, "suppressed" => 0, "queued" => 1, "accepted" => 2, "sent" => 3,
      "delivered" => 4, "undelivered" => 4, "failed" => 4, "read" => 5
    }.freeze
    RECLAIMABLE = %w[pending failed suppressed].freeze
    TERMINAL_FAILURES = %w[undelivered failed].freeze

    # A claim older than this is treated as abandoned by a crashed worker.
    CLAIM_TIMEOUT = 2.minutes

    enum :status, STATUSES.index_with(&:itself)

    belongs_to :recipient, polymorphic: true, optional: true

    scope :recent, -> { order(created_at: :desc) }
    scope :for_number, ->(number) { where(to_number: number) }

    class << self
      # Create or reuse the delivery row for +message+ and claim it for
      # sending. Returns nil when an identical message was already sent
      # inside the dedupe window, or another worker holds the claim.
      def claim_for(message, provider:)
        key = Smswire.config.dedupe_window ? message.idempotency_key : nil

        if key && (existing = find_by(idempotency_key: key))
          if existing.created_at < Smswire.config.dedupe_window.ago
            where(id: existing.id, idempotency_key: key).update_all(idempotency_key: nil)
          else
            return existing.claim
          end
        end

        create!(attributes_for(message, provider:).merge(
          idempotency_key: key, status: "pending", attempts: 1, claimed_at: Time.current
        ))
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      # Apply a provider status callback. Looks up by delivery id when the
      # callback URL carried one, falling back to the provider message id.
      def apply_status_update(update, provider:, delivery_id: nil)
        delivery = find_by(id: delivery_id, provider: provider.to_s) if delivery_id.present?
        if delivery.nil? || (delivery.provider_id.present? && delivery.provider_id != update.provider_id)
          delivery = find_by(provider: provider.to_s, provider_id: update.provider_id)
        end
        delivery&.advance!(update.status, provider_id: update.provider_id,
          error_code: update.error_code, error_message: update.error_message)
        delivery
      end

      def attributes_for(message, provider:)
        record = message.recipient&.record
        {
          messenger: message.messenger,
          action: message.action,
          to_number: message.to,
          from_number: message.from,
          messaging_service: message.messaging_service,
          recipient: (record if record.is_a?(ActiveRecord::Base) && record.persisted?),
          category: message.category.to_s,
          body: (message.body if Smswire.config.store_body?(message.category)),
          segments: message.segments,
          encoding: message.encoding.to_s,
          provider: provider.to_s,
          metadata: message.metadata.presence
        }
      end
    end

    # Atomically claim a reusable row for another send attempt.
    def claim
      return nil unless RECLAIMABLE.include?(status)

      now = Time.current
      claimed = self.class
        .where(id:, status: RECLAIMABLE)
        .where("claimed_at IS NULL OR claimed_at < ?", now - CLAIM_TIMEOUT)
        .update_all(["claimed_at = ?, attempts = attempts + 1, status = 'pending', " \
                     "error_code = NULL, error_message = NULL, failed_at = NULL, updated_at = ?", now, now])
      reload if claimed == 1
    end

    def record_receipt!(receipt, message)
      now = Time.current
      with_lock do
        assign_attributes(final_message_attributes(message))
        assign_attributes(provider_id: receipt.provider_id, segments: receipt.segments || message.segments,
          price_amount: receipt.price_amount, price_currency: receipt.price_currency,
          sent_at: now, claimed_at: nil)
        apply_status(receipt.status.to_s, now) if progresses_to?(receipt.status)
        save!
      end
    end

    def record_failure!(error, message)
      update!(final_message_attributes(message).merge(
        status: "failed", error_code: error.provider_code, error_message: error.message,
        failed_at: Time.current, status_updated_at: Time.current, claimed_at: nil
      ))
    end

    # Release the claim after a transient error so a retry can reclaim it.
    def release!(error)
      update!(claimed_at: nil, error_code: error.provider_code, error_message: error.message)
    end

    def record_suppression!(message)
      update!(final_message_attributes(message).merge(status: "suppressed", claimed_at: nil, status_updated_at: Time.current))
    end

    def advance!(new_status, provider_id: nil, error_code: nil, error_message: nil)
      with_lock do
        self.provider_id ||= provider_id
        if progresses_to?(new_status)
          apply_status(new_status.to_s, Time.current)
          self.error_code = error_code if error_code.present?
          self.error_message = error_message if error_message.present?
        end
        save!
      end
    end

    def progresses_to?(new_status)
      PROGRESS.fetch(new_status.to_s) > PROGRESS.fetch(status)
    end

    private

    def apply_status(new_status, at)
      self.status = new_status
      self.status_updated_at = at
      self.delivered_at = at if new_status == "delivered"
      self.failed_at = at if TERMINAL_FAILURES.include?(new_status)
    end

    def final_message_attributes(message)
      {
        to_number: message.to,
        from_number: message.from,
        messaging_service: message.messaging_service,
        body: (message.body if Smswire.config.store_body?(message.category)),
        segments: message.segments,
        encoding: message.encoding.to_s
      }
    end
  end
end
