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

ActiveRecord::Schema[8.1].define(version: 2026_05_07_100001) do
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
    t.integer "oauth_authorization_request_id"
    t.string "pending_user_id", null: false
    t.datetime "used_at"
    t.string "verify_token", null: false
    t.index ["email"], name: "index_email_verifications_on_email"
    t.index ["expires_at"], name: "index_email_verifications_on_expires_at"
    t.index ["oauth_authorization_request_id"], name: "index_email_verifications_on_oauth_authorization_request_id"
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

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.integer "oauth_client_id", null: false
    t.string "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.datetime "refresh_token_used_at"
    t.string "resource", null: false
    t.datetime "revoked_at"
    t.string "scope", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["expires_at"], name: "index_oauth_access_tokens_on_expires_at"
    t.index ["oauth_client_id"], name: "index_oauth_access_tokens_on_oauth_client_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["refresh_token_expires_at"], name: "index_oauth_access_tokens_on_refresh_token_expires_at"
    t.index ["revoked_at"], name: "index_oauth_access_tokens_on_revoked_at"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_oauth_access_tokens_on_user_id"
  end

  create_table "oauth_audit_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event", null: false
    t.string "ip_address", limit: 45
    t.text "metadata"
    t.integer "oauth_access_token_id"
    t.integer "oauth_client_id"
    t.integer "user_id"
    t.index ["created_at"], name: "index_oauth_audit_events_on_created_at"
    t.index ["event"], name: "index_oauth_audit_events_on_event"
    t.index ["oauth_access_token_id"], name: "index_oauth_audit_events_on_oauth_access_token_id"
    t.index ["oauth_client_id"], name: "index_oauth_audit_events_on_oauth_client_id"
    t.index ["user_id"], name: "index_oauth_audit_events_on_user_id"
  end

  create_table "oauth_authorization_codes", force: :cascade do |t|
    t.string "code", null: false
    t.string "code_challenge", null: false
    t.string "code_challenge_method", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "oauth_client_id", null: false
    t.string "redirect_uri", null: false
    t.string "resource"
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["code"], name: "index_oauth_authorization_codes_on_code", unique: true
    t.index ["expires_at"], name: "index_oauth_authorization_codes_on_expires_at"
    t.index ["oauth_client_id"], name: "index_oauth_authorization_codes_on_oauth_client_id"
    t.index ["user_id"], name: "index_oauth_authorization_codes_on_user_id"
  end

  create_table "oauth_authorization_requests", force: :cascade do |t|
    t.string "code_challenge", null: false
    t.string "code_challenge_method", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "expires_at", null: false
    t.integer "oauth_client_id", null: false
    t.string "redirect_uri", null: false
    t.string "request_token", null: false
    t.string "resource"
    t.string "scope", default: "analytics:read analytics:manage", null: false
    t.string "state"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["expires_at"], name: "index_oauth_authorization_requests_on_expires_at"
    t.index ["oauth_client_id"], name: "index_oauth_authorization_requests_on_oauth_client_id"
    t.index ["request_token"], name: "index_oauth_authorization_requests_on_request_token", unique: true
    t.index ["user_id"], name: "index_oauth_authorization_requests_on_user_id"
  end

  create_table "oauth_clients", force: :cascade do |t|
    t.string "client_id", null: false
    t.string "client_name", null: false
    t.string "client_uri"
    t.datetime "created_at", null: false
    t.boolean "dynamically_registered", default: false, null: false
    t.string "grant_types", default: "authorization_code", null: false
    t.string "logo_uri"
    t.text "redirect_uris", null: false
    t.string "response_types", default: "code", null: false
    t.string "scope", default: "analytics:read analytics:manage", null: false
    t.string "token_endpoint_auth_method", default: "none", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_oauth_clients_on_client_id", unique: true
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
    t.integer "session_version", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "email_verifications", "oauth_authorization_requests"
  add_foreign_key "magic_links", "users"
  add_foreign_key "oauth_access_tokens", "oauth_clients"
  add_foreign_key "oauth_access_tokens", "users"
  add_foreign_key "oauth_audit_events", "oauth_access_tokens"
  add_foreign_key "oauth_audit_events", "oauth_clients"
  add_foreign_key "oauth_audit_events", "users"
  add_foreign_key "oauth_authorization_codes", "oauth_clients"
  add_foreign_key "oauth_authorization_codes", "users"
  add_foreign_key "oauth_authorization_requests", "oauth_clients"
  add_foreign_key "oauth_authorization_requests", "users"
  add_foreign_key "sites", "users"
end
