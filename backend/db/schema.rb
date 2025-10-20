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

ActiveRecord::Schema[8.0].define(version: 2025_10_20_184419) do
  create_table "acknowledgements", force: :cascade do |t|
    t.integer "occurrence_id", null: false
    t.integer "kind", null: false
    t.datetime "at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["occurrence_id"], name: "index_acknowledgements_on_occurrence_id"
  end

  create_table "caregiver_availabilities", force: :cascade do |t|
    t.integer "caregiver_id", null: false
    t.date "date", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["caregiver_id", "date"], name: "index_caregiver_availabilities_on_caregiver_id_and_date"
    t.index ["caregiver_id"], name: "index_caregiver_availabilities_on_caregiver_id"
    t.index ["date"], name: "index_caregiver_availabilities_on_date"
  end

  create_table "caregiver_links", force: :cascade do |t|
    t.integer "senior_id", null: false
    t.integer "caregiver_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "permission", default: 0, null: false
    t.string "pairing_token"
    t.index ["pairing_token"], name: "index_caregiver_links_on_pairing_token", unique: true
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
    t.datetime "start_time"
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "task_comments", force: :cascade do |t|
    t.integer "task_id", null: false
    t.integer "user_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "created_at"], name: "index_task_comments_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_task_comments_on_task_id"
    t.index ["user_id"], name: "index_task_comments_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "senior_id", null: false
    t.integer "assigned_to_id"
    t.integer "created_by_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "task_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.datetime "scheduled_at", null: false
    t.integer "duration_minutes"
    t.string "location"
    t.text "notes"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "visible_to_senior", default: true, null: false
    t.index ["assigned_to_id", "status"], name: "index_tasks_on_assigned_to_id_and_status"
    t.index ["assigned_to_id"], name: "index_tasks_on_assigned_to_id"
    t.index ["created_by_id"], name: "index_tasks_on_created_by_id"
    t.index ["scheduled_at"], name: "index_tasks_on_scheduled_at"
    t.index ["senior_id", "scheduled_at"], name: "index_tasks_on_senior_id_and_scheduled_at"
    t.index ["senior_id"], name: "index_tasks_on_senior_id"
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["task_type"], name: "index_tasks_on_task_type"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.integer "role"
    t.string "tz", default: "America/New_York"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "nickname"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "acknowledgements", "occurrences"
  add_foreign_key "caregiver_availabilities", "users", column: "caregiver_id"
  add_foreign_key "caregiver_links", "users", column: "caregiver_id"
  add_foreign_key "caregiver_links", "users", column: "senior_id"
  add_foreign_key "occurrences", "reminders"
  add_foreign_key "reminders", "users"
  add_foreign_key "task_comments", "tasks"
  add_foreign_key "task_comments", "users"
  add_foreign_key "tasks", "users", column: "assigned_to_id"
  add_foreign_key "tasks", "users", column: "created_by_id"
  add_foreign_key "tasks", "users", column: "senior_id"
end
