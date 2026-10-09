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

ActiveRecord::Schema[8.1].define(version: 2026_10_09_123000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "identities", "users"
  add_foreign_key "leads", "quotes"
  add_foreign_key "operational_email_consent_events", "users"
  add_foreign_key "quotes", "users"
  add_foreign_key "sessions", "users"
end
