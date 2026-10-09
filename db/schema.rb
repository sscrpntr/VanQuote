# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_09_180000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "anonymous_quote_counters", force: :cascade do |t|
    t.string "fingerprint", null: false
    t.integer "requests_count", default: 0, null: false
    t.datetime "window_started_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_anonymous_quote_counters_on_fingerprint", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "leads", force: :cascade do |t|
    t.bigint "quote_id", null: false
    t.string "email", null: false
    t.boolean "consent_given", null: false
    t.datetime "consent_at", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contact_preference"
    t.string "phone"
    t.string "consent_basis"
    t.datetime "consent_withdrawn_at"
    t.datetime "admin_notification_sent_at"
    t.index ["quote_id"], name: "idx_leads_quote_uidx", unique: true
    t.index ["quote_id"], name: "index_leads_on_quote_id"
  end

  create_table "operational_email_consent_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "action", null: false
    t.string "text_version"
    t.string "purpose", null: false
    t.text "consent_text"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_operational_email_consent_events_on_user_id"
  end

  create_table "password_reset_rate_limits", force: :cascade do |t|
    t.string "scope", null: false
    t.string "key_digest", limit: 64, null: false
    t.integer "request_count", default: 0, null: false
    t.datetime "window_started_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "idx_password_reset_rate_limits_expiry"
    t.index ["scope", "key_digest"], name: "idx_password_reset_rate_limits_scope_key", unique: true
    t.check_constraint "expires_at > window_started_at", name: "prrl_valid_window"
    t.check_constraint "request_count > 0", name: "prrl_positive_count"
    t.check_constraint "scope::text = ANY (ARRAY['ip'::character varying, 'account'::character varying]::text[])", name: "prrl_valid_scope"
  end

  create_table "quote_creation_requests", force: :cascade do |t|
    t.string "key_digest", null: false
    t.string "request_digest", null: false
    t.bigint "user_id"
    t.string "anonymous_session_digest"
    t.string "status", default: "pending", null: false
    t.string "claim_token"
    t.datetime "lease_expires_at"
    t.datetime "anonymous_counted_at"
    t.bigint "quote_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_digest"], name: "idx_qcr_key_uidx", unique: true
    t.index ["quote_id"], name: "idx_qcr_quote_uidx", unique: true
    t.index ["user_id"], name: "idx_qcr_user"
    t.check_constraint "status::text <> 'processing'::text OR claim_token IS NOT NULL AND lease_expires_at IS NOT NULL", name: "qcr_processing_lease"
    t.check_constraint "status::text = 'completed'::text AND quote_id IS NOT NULL AND claim_token IS NULL AND lease_expires_at IS NULL OR status::text <> 'completed'::text AND quote_id IS NULL", name: "qcr_completed_quote_state"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'failed'::character varying, 'completed'::character varying]::text[])", name: "qcr_valid_status"
    t.check_constraint "user_id IS NOT NULL AND anonymous_session_digest IS NULL OR user_id IS NULL AND anonymous_session_digest IS NOT NULL", name: "qcr_requester_scope"
  end

  create_table "quotes", force: :cascade do |t|
    t.string "origin"
    t.string "destination"
    t.decimal "distance_km"
    t.integer "estimated_duration_minutes"
    t.decimal "fuel_cost"
    t.decimal "toll_cost"
    t.decimal "vehicle_cost"
    t.decimal "driver_cost"
    t.decimal "loading_cost"
    t.decimal "waiting_cost"
    t.decimal "other_cost"
    t.decimal "total_cost"
    t.decimal "margin"
    t.decimal "recommended_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "contact_email"
    t.datetime "result_email_sent_at"
    t.index ["user_id"], name: "index_quotes_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "user_agent"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "phone"
    t.boolean "operational_email_consent", default: false, null: false
    t.datetime "operational_email_consent_at"
    t.string "operational_email_consent_text_version"
    t.string "operational_email_consent_purpose"
    t.datetime "terms_accepted_at"
    t.string "terms_version"
    t.datetime "email_verified_at"
    t.integer "password_reset_generation", default: 0, null: false
    t.index ["admin"], name: "idx_users_single_admin_uidx", unique: true, where: "(admin = true)"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "identities", "users"
  add_foreign_key "leads", "quotes"
  add_foreign_key "operational_email_consent_events", "users"
  add_foreign_key "quote_creation_requests", "quotes"
  add_foreign_key "quote_creation_requests", "users"
  add_foreign_key "quotes", "users"
  add_foreign_key "sessions", "users"
end
