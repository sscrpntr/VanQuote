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

ActiveRecord::Schema[8.1].define(version: 2026_10_06_054356) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "leads", force: :cascade do |t|
    t.bigint "quote_id", null: false
    t.string "email", null: false
    t.boolean "consent_given", null: false
    t.datetime "consent_at", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contact_preference"
    t.index ["quote_id"], name: "index_leads_on_quote_id"
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
  end

  add_foreign_key "leads", "quotes"
end
