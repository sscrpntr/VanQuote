class HardenPasswordResetFlow < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_reset_generation, :integer, null: false, default: 0

    create_table :password_reset_rate_limits do |t|
      t.string :scope, null: false
      t.string :key_digest, null: false, limit: 64
      t.integer :request_count, null: false, default: 0
      t.datetime :window_started_at, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :password_reset_rate_limits, [ :scope, :key_digest ],
      unique: true, name: "idx_password_reset_rate_limits_scope_key"
    add_index :password_reset_rate_limits, :expires_at,
      name: "idx_password_reset_rate_limits_expiry"

    add_check_constraint :password_reset_rate_limits,
      "scope IN ('ip', 'account')", name: "prrl_valid_scope"
    add_check_constraint :password_reset_rate_limits,
      "request_count > 0", name: "prrl_positive_count"
    add_check_constraint :password_reset_rate_limits,
      "expires_at > window_started_at", name: "prrl_valid_window"
  end
end
