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

ActiveRecord::Schema[8.0].define(version: 2025_10_05_234541) do
  create_table "acknowledgements", force: :cascade do |t|
    t.integer "occurrence_id", null: false
    t.integer "kind", null: false
    t.datetime "at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["occurrence_id"], name: "index_acknowledgements_on_occurrence_id"
  end

  create_table "caregiver_links", force: :cascade do |t|
    t.integer "senior_id", null: false
    t.integer "caregiver_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["senior_id", "caregiver_id"], name: "index_caregiver_links_on_senior_id_and_caregiver_id", unique: true
  end

  create_table "occurrences", force: :cascade do |t|
    t.integer "reminder_id", null: false
    t.datetime "scheduled_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reminder_id", "scheduled_at"], name: "index_occurrences_on_reminder_id_and_scheduled_at", unique: true
    t.index ["reminder_id"], name: "index_occurrences_on_reminder_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.text "notes"
    t.string "rrule", null: false
    t.string "tz", null: false
    t.integer "category", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.integer "role", default: 0, null: false
    t.string "tz", default: "America/New_York"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "acknowledgements", "occurrences"
  add_foreign_key "caregiver_links", "users", column: "caregiver_id"
  add_foreign_key "caregiver_links", "users", column: "senior_id"
  add_foreign_key "occurrences", "reminders"
  add_foreign_key "reminders", "users"
end
