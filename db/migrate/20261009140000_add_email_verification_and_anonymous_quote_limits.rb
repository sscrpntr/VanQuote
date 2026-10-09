class AddEmailVerificationAndAnonymousQuoteLimits < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verified_at, :datetime

    create_table :anonymous_quote_counters do |t|
      t.string :fingerprint, null: false
      t.integer :requests_count, null: false, default: 0
      t.datetime :window_started_at, null: false
      t.timestamps
    end
    add_index :anonymous_quote_counters, :fingerprint, unique: true
  end
end
