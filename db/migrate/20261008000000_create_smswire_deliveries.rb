class CreateSmswireDeliveries < ActiveRecord::Migration[7.1]
  def change
    primary_key_type, foreign_key_type = primary_and_foreign_key_types

    create_table :smswire_deliveries, id: primary_key_type do |t|
      t.string :messenger
      t.string :action
      t.string :to_number, null: false
      t.string :from_number
      t.string :messaging_service
      t.references :recipient, polymorphic: true, type: foreign_key_type, index: true
      t.string :category, null: false
      t.text :body
      t.integer :segments
      t.string :encoding
      t.string :provider, null: false
      t.string :provider_id
      t.string :status, null: false, default: "pending"
      t.string :error_code
      t.text :error_message
      t.string :idempotency_key
      t.decimal :price_amount, precision: 12, scale: 5
      t.string :price_currency
      t.json :metadata
      t.integer :attempts, null: false, default: 0
      t.datetime :claimed_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.datetime :status_updated_at
      t.timestamps
    end

    add_index :smswire_deliveries, [:provider, :provider_id], unique: true
    add_index :smswire_deliveries, :idempotency_key, unique: true
    add_index :smswire_deliveries, [:to_number, :created_at]
    add_index :smswire_deliveries, [:status, :created_at]
  end

  private

  def primary_and_foreign_key_types
    config = Rails.configuration.generators
    setting = config.options[config.orm][:primary_key_type]
    [setting || :primary_key, setting || :bigint]
  end
end
