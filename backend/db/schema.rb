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

ActiveRecord::Schema[8.0].define(version: 2025_11_07_184300) do
  create_table "acknowledgements", force: :cascade do |t|
    t.integer "occurrence_id", null: false
    t.integer "kind", null: false
    t.datetime "at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["occurrence_id"], name: "index_acknowledgements_on_occurrence_id"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.integer "visit_id"
    t.integer "user_id"
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.integer "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
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

  create_table "scheduling_integrations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "senior_id"
    t.integer "provider", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "provider_user_id", null: false
    t.string "api_key"
    t.string "api_secret"
    t.string "access_token"
    t.string "webhook_secret"
    t.datetime "last_synced_at"
    t.boolean "sync_enabled", default: true, null: false
    t.json "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_scheduling_integrations_on_provider"
    t.index ["senior_id", "provider"], name: "index_scheduling_integrations_on_senior_id_and_provider"
    t.index ["senior_id"], name: "index_scheduling_integrations_on_senior_id"
    t.index ["status"], name: "index_scheduling_integrations_on_status"
    t.index ["user_id", "provider"], name: "index_scheduling_integrations_on_user_id_and_provider"
    t.index ["user_id"], name: "index_scheduling_integrations_on_user_id"
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
    t.integer "scheduling_integration_id"
    t.string "external_source"
    t.string "external_id"
    t.string "external_url"
    t.json "sync_metadata", default: {}
    t.index ["assigned_to_id", "status"], name: "index_tasks_on_assigned_to_id_and_status"
    t.index ["assigned_to_id"], name: "index_tasks_on_assigned_to_id"
    t.index ["created_by_id"], name: "index_tasks_on_created_by_id"
    t.index ["external_source", "external_id"], name: "index_tasks_on_external_source_and_external_id", unique: true, where: "external_source IS NOT NULL"
    t.index ["external_source"], name: "index_tasks_on_external_source"
    t.index ["scheduled_at"], name: "index_tasks_on_scheduled_at"
    t.index ["scheduling_integration_id"], name: "index_tasks_on_scheduling_integration_id"
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
  add_foreign_key "scheduling_integrations", "users"
  add_foreign_key "scheduling_integrations", "users", column: "senior_id"
  add_foreign_key "task_comments", "tasks"
  add_foreign_key "task_comments", "users"
  add_foreign_key "tasks", "scheduling_integrations"
  add_foreign_key "tasks", "users", column: "assigned_to_id"
  add_foreign_key "tasks", "users", column: "created_by_id"
  add_foreign_key "tasks", "users", column: "senior_id"
end
