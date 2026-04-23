class CreateAbuseEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :abuse_events do |t|
      t.string :ip, null: false
      t.string :kind, null: false, default: "garbage_site_ids"
      t.integer :unique_sites, null: false, default: 0
      t.datetime :blocked_until, null: false
      t.datetime :notified_at
      t.timestamps
    end

    add_index :abuse_events, :notified_at
    add_index :abuse_events, :created_at
  end
end
