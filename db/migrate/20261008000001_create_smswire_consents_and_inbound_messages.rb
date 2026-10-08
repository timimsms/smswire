class CreateSmswireConsentsAndInboundMessages < ActiveRecord::Migration[7.1]
  def change
    primary_key_type = Rails.configuration.generators.options[Rails.configuration.generators.orm][:primary_key_type]

    create_table :smswire_consents, id: primary_key_type || :primary_key do |t|
      t.string :phone, null: false
      t.string :scope, null: false, default: "default"
      t.string :status, null: false, default: "unknown"
      t.string :source
      t.datetime :opted_in_at
      t.datetime :opted_out_at
      t.string :last_keyword
      t.datetime :last_keyword_at
      t.json :metadata
      t.timestamps
    end
    add_index :smswire_consents, [:phone, :scope], unique: true

    create_table :smswire_inbound_messages, id: primary_key_type || :primary_key do |t|
      t.string :provider, null: false
      t.string :provider_id, null: false
      t.string :from_number, null: false
      t.string :to_number
      t.string :messaging_service
      t.text :body
      t.string :keyword
      t.datetime :handled_at
      t.json :raw
      t.timestamps
    end
    add_index :smswire_inbound_messages, [:provider, :provider_id], unique: true
    add_index :smswire_inbound_messages, [:from_number, :created_at]
  end
end
