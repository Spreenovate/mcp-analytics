class CreateSites < ActiveRecord::Migration[8.1]
  def change
    create_table :sites do |t|
      t.references :user, null: false, foreign_key: true
      t.string :domain, null: false
      t.string :site_id, null: false
      t.string :privacy_mode, null: false, default: "strict"
      t.string :site_salt, null: false
      t.datetime :salt_rotated_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :sites, :site_id, unique: true
    add_index :sites, [:user_id, :domain]
    add_index :sites, :deleted_at
  end
end
