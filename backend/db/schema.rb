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

ActiveRecord::Schema[8.1].define(version: 2026_08_28_231943) do
  create_table "acknowledgements", force: :cascade do |t|
    t.datetime "at", null: false
    t.datetime "created_at", null: false
    t.integer "kind", null: false
    t.integer "occurrence_id", null: false
    t.datetime "updated_at", null: false
    t.index ["occurrence_id"], name: "index_acknowledgements_on_occurrence_id"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.integer "user_id"
    t.integer "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.integer "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "caregiver_availabilities", force: :cascade do |t|
    t.integer "caregiver_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.time "end_time", null: false
    t.text "notes"
    t.time "start_time", null: false
    t.datetime "updated_at", null: false
    t.index ["caregiver_id", "date"], name: "index_caregiver_availabilities_on_caregiver_id_and_date"
    t.index ["caregiver_id"], name: "index_caregiver_availabilities_on_caregiver_id"
    t.index ["date"], name: "index_caregiver_availabilities_on_date"
  end

  create_table "caregiver_links", force: :cascade do |t|
    t.integer "caregiver_id"
    t.datetime "created_at", null: false
    t.string "pairing_token"
    t.integer "permission", default: 0, null: false
    t.integer "senior_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pairing_token"], name: "index_caregiver_links_on_pairing_token", unique: true
    t.index ["senior_id", "caregiver_id"], name: "index_caregiver_links_on_senior_id_and_caregiver_id", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "message"
    t.json "metadata"
    t.string "notification_type", null: false
    t.integer "occurrence_id"
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["notification_type"], name: "index_notifications_on_notification_type"
    t.index ["user_id", "notification_type", "occurrence_id"], name: "index_notifications_on_user_type_and_occurrence", unique: true, where: "occurrence_id IS NOT NULL"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "occurrences", force: :cascade do |t|
    t.datetime "call_suppressed_at"
    t.string "call_suppressed_reason"
    t.datetime "created_at", null: false
    t.integer "reminder_id", null: false
    t.datetime "scheduled_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["reminder_id", "scheduled_at"], name: "index_occurrences_on_reminder_id_and_scheduled_at", unique: true
    t.index ["reminder_id"], name: "index_occurrences_on_reminder_id"
    t.index ["status", "scheduled_at"], name: "index_occurrences_on_status_and_scheduled_at"
  end

  create_table "page_counts", force: :cascade do |t|
    t.boolean "bot", default: false, null: false
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "day", null: false
    t.string "path", null: false
    t.string "referrer_host", default: "", null: false
    t.string "source", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["day", "path", "referrer_host", "source", "bot"], name: "index_page_counts_on_dimensions", unique: true
    t.index ["day"], name: "index_page_counts_on_day"
  end

  create_table "reminders", force: :cascade do |t|
    t.integer "category", default: 0
    t.datetime "created_at", null: false
    t.text "notes"
    t.string "rrule", null: false
    t.datetime "start_time"
    t.string "title", null: false
    t.string "tz", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "scheduling_integrations", force: :cascade do |t|
    t.string "access_token"
    t.string "api_key"
    t.string "api_secret"
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.integer "provider", default: 0, null: false
    t.string "provider_user_id", null: false
    t.integer "senior_id"
    t.json "settings", default: {}
    t.integer "status", default: 0, null: false
    t.boolean "sync_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "webhook_secret"
    t.index ["provider"], name: "index_scheduling_integrations_on_provider"
    t.index ["senior_id", "provider"], name: "index_scheduling_integrations_on_senior_id_and_provider"
    t.index ["senior_id"], name: "index_scheduling_integrations_on_senior_id"
    t.index ["status"], name: "index_scheduling_integrations_on_status"
    t.index ["user_id", "provider"], name: "index_scheduling_integrations_on_user_id_and_provider"
    t.index ["user_id"], name: "index_scheduling_integrations_on_user_id"
  end

  create_table "subscribers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_subscribers_on_email", unique: true
  end

  create_table "task_comments", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["task_id", "created_at"], name: "index_task_comments_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_task_comments_on_task_id"
    t.index ["user_id"], name: "index_task_comments_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "assigned_to_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.text "description"
    t.integer "duration_minutes"
    t.string "external_id"
    t.string "external_source"
    t.string "external_url"
    t.string "location"
    t.text "notes"
    t.integer "parent_task_id"
    t.integer "priority", default: 1, null: false
    t.string "rrule"
    t.datetime "scheduled_at"
    t.integer "scheduling_integration_id"
    t.integer "senior_id", null: false
    t.datetime "start_time"
    t.integer "status", default: 0, null: false
    t.json "sync_metadata", default: {}
    t.integer "task_type", default: 0, null: false
    t.string "title", null: false
    t.string "tz"
    t.datetime "updated_at", null: false
    t.boolean "visible_to_senior", default: true, null: false
    t.index ["assigned_to_id", "status"], name: "index_tasks_on_assigned_to_id_and_status"
    t.index ["assigned_to_id"], name: "index_tasks_on_assigned_to_id"
    t.index ["created_by_id"], name: "index_tasks_on_created_by_id"
    t.index ["external_source", "external_id"], name: "index_tasks_on_external_source_and_external_id", unique: true, where: "external_source IS NOT NULL"
    t.index ["external_source"], name: "index_tasks_on_external_source"
    t.index ["parent_task_id", "scheduled_at"], name: "index_tasks_on_parent_task_id_and_scheduled_at", unique: true, where: "parent_task_id IS NOT NULL"
    t.index ["parent_task_id"], name: "index_tasks_on_parent_task_id"
    t.index ["rrule"], name: "index_tasks_on_rrule"
    t.index ["scheduled_at"], name: "index_tasks_on_scheduled_at"
    t.index ["scheduling_integration_id"], name: "index_tasks_on_scheduling_integration_id"
    t.index ["senior_id", "scheduled_at"], name: "index_tasks_on_senior_id_and_scheduled_at"
    t.index ["senior_id"], name: "index_tasks_on_senior_id"
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["task_type"], name: "index_tasks_on_task_type"
  end

  create_table "telnyx_calls", force: :cascade do |t|
    t.datetime "answered_at"
    t.integer "attempt_number", default: 1, null: false
    t.string "call_control_id"
    t.date "call_day"
    t.string "call_leg_id"
    t.string "call_tz"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "daily_sequence"
    t.string "dtmf"
    t.text "last_payload"
    t.integer "occurrence_id"
    t.string "outcome", default: "pending", null: false
    t.string "purpose", default: "reminder", null: false
    t.integer "requested_by_id"
    t.string "status", default: "pending", null: false
    t.string "to_number"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["call_control_id"], name: "index_telnyx_calls_on_call_control_id", unique: true
    t.index ["call_leg_id"], name: "index_telnyx_calls_on_call_leg_id", unique: true, where: "call_leg_id IS NOT NULL"
    t.index ["occurrence_id", "attempt_number"], name: "index_telnyx_calls_on_occurrence_and_attempt", unique: true
    t.index ["occurrence_id"], name: "index_telnyx_calls_on_occurrence_id"
    t.index ["requested_by_id"], name: "index_telnyx_calls_on_requested_by_id"
    t.index ["to_number", "call_day", "attempt_number"], name: "index_telnyx_calls_on_number_day_and_verification_attempt", unique: true, where: "purpose = 'verification' AND to_number IS NOT NULL"
    t.index ["to_number"], name: "index_telnyx_calls_one_live_call_per_number", unique: true, where: "completed_at IS NULL AND to_number IS NOT NULL"
    t.index ["user_id", "call_day", "daily_sequence"], name: "index_telnyx_calls_on_user_day_and_sequence", unique: true, where: "call_day IS NOT NULL"
    t.index ["user_id", "purpose", "call_day"], name: "index_telnyx_calls_on_user_purpose_and_day"
    t.index ["user_id"], name: "index_telnyx_calls_on_user_id"
  end

  create_table "time_blocks", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "end_time", null: false
    t.string "reason"
    t.string "recurrence_pattern"
    t.boolean "recurring", default: false, null: false
    t.datetime "start_time", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["active"], name: "index_time_blocks_on_active"
    t.index ["user_id", "start_time", "end_time"], name: "index_time_blocks_on_user_id_and_start_time_and_end_time"
    t.index ["user_id"], name: "index_time_blocks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "call_consent_at"
    t.datetime "call_opted_out_at"
    t.boolean "call_reminders_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "email_undeliverable_at"
    t.string "name"
    t.string "nickname"
    t.boolean "notify_on_coverage_gaps", default: true, null: false
    t.boolean "notify_on_task_assigned_to_others", default: false
    t.json "notify_reminder_categories", default: ["medication"], null: false
    t.string "phone"
    t.datetime "phone_verified_at"
    t.integer "role"
    t.string "spoken_language", default: "en-US", null: false
    t.integer "text_size", default: 0, null: false
    t.string "tz", default: "America/New_York"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "acknowledgements", "occurrences"
  add_foreign_key "caregiver_availabilities", "users", column: "caregiver_id"
  add_foreign_key "caregiver_links", "users", column: "caregiver_id"
  add_foreign_key "caregiver_links", "users", column: "senior_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "occurrences", "reminders"
  add_foreign_key "reminders", "users"
  add_foreign_key "scheduling_integrations", "users"
  add_foreign_key "scheduling_integrations", "users", column: "senior_id"
  add_foreign_key "task_comments", "tasks"
  add_foreign_key "task_comments", "users"
  add_foreign_key "tasks", "scheduling_integrations"
  add_foreign_key "tasks", "tasks", column: "parent_task_id"
  add_foreign_key "tasks", "users", column: "assigned_to_id"
  add_foreign_key "tasks", "users", column: "created_by_id"
  add_foreign_key "tasks", "users", column: "senior_id"
  add_foreign_key "telnyx_calls", "occurrences"
  add_foreign_key "telnyx_calls", "users"
  add_foreign_key "telnyx_calls", "users", column: "requested_by_id"
  add_foreign_key "time_blocks", "users"
end
