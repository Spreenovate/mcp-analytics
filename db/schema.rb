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

ActiveRecord::Schema[8.1].define(version: 2026_04_23_100007) do
  create_table "abuse_events", force: :cascade do |t|
    t.datetime "blocked_until", null: false
    t.datetime "created_at", null: false
    t.string "ip", null: false
    t.string "kind", default: "garbage_site_ids", null: false
    t.datetime "notified_at"
    t.integer "unique_sites", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_abuse_events_on_created_at"
    t.index ["notified_at"], name: "index_abuse_events_on_notified_at"
  end

  create_table "email_verifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.string "pending_user_id", null: false
    t.datetime "used_at"
    t.string "verify_token", null: false
    t.index ["email"], name: "index_email_verifications_on_email"
    t.index ["expires_at"], name: "index_email_verifications_on_expires_at"
    t.index ["pending_user_id"], name: "index_email_verifications_on_pending_user_id", unique: true
    t.index ["verify_token"], name: "index_email_verifications_on_verify_token", unique: true
  end

  create_table "magic_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["expires_at"], name: "index_magic_links_on_expires_at"
    t.index ["token"], name: "index_magic_links_on_token", unique: true
    t.index ["user_id"], name: "index_magic_links_on_user_id"
  end

  create_table "sites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "domain", null: false
    t.string "privacy_mode", default: "strict", null: false
    t.datetime "salt_rotated_at"
    t.string "site_id", null: false
    t.string "site_salt", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["deleted_at"], name: "index_sites_on_deleted_at"
    t.index ["site_id"], name: "index_sites_on_site_id", unique: true
    t.index ["user_id", "domain"], name: "index_sites_on_user_id_and_domain"
    t.index ["user_id"], name: "index_sites_on_user_id"
  end

  create_table "unknown_site_hits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "hit_count", default: 0, null: false
    t.datetime "hour", null: false
    t.string "site_id_attempted", null: false
    t.datetime "updated_at", null: false
    t.index ["hour"], name: "index_unknown_site_hits_on_hour"
    t.index ["site_id_attempted", "hour"], name: "index_unknown_site_hits_on_site_id_attempted_and_hour", unique: true
  end

  create_table "usage_counters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "hit_count", default: 0, null: false
    t.date "month", null: false
    t.string "site_id", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "month"], name: "index_usage_counters_on_site_id_and_month", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "email_verified_at"
    t.string "plan", default: "free", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "magic_links", "users"
  add_foreign_key "sites", "users"
end
