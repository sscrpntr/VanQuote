class CreateQuoteCreationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :quote_creation_requests do |t|
      t.string :key_digest, null: false
      t.string :request_digest, null: false
      t.references :user, foreign_key: true, index: { name: "idx_qcr_user" }
      t.string :anonymous_session_digest
      t.string :status, null: false, default: "pending"
      t.string :claim_token
      t.datetime :lease_expires_at
      t.datetime :anonymous_counted_at
      t.references :quote, foreign_key: true, index: { unique: true, name: "idx_qcr_quote_uidx" }
      t.timestamps
    end

    add_index :quote_creation_requests, :key_digest, unique: true, name: "idx_qcr_key_uidx"
    add_check_constraint :quote_creation_requests,
      "status IN ('pending', 'processing', 'failed', 'completed')",
      name: "qcr_valid_status"
    add_check_constraint :quote_creation_requests,
      "(user_id IS NOT NULL AND anonymous_session_digest IS NULL) OR " \
        "(user_id IS NULL AND anonymous_session_digest IS NOT NULL)",
      name: "qcr_requester_scope"
    add_check_constraint :quote_creation_requests,
      "(status = 'completed' AND quote_id IS NOT NULL AND claim_token IS NULL AND lease_expires_at IS NULL) OR " \
        "(status <> 'completed' AND quote_id IS NULL)",
      name: "qcr_completed_quote_state"
    add_check_constraint :quote_creation_requests,
      "status <> 'processing' OR (claim_token IS NOT NULL AND lease_expires_at IS NOT NULL)",
      name: "qcr_processing_lease"
  end
end
