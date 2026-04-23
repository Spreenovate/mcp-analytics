class CreateUnknownSiteHits < ActiveRecord::Migration[8.1]
  def change
    create_table :unknown_site_hits do |t|
      t.string :site_id_attempted, null: false
      t.datetime :hour, null: false
      t.bigint :hit_count, null: false, default: 0
      t.timestamps
    end

    add_index :unknown_site_hits, [:site_id_attempted, :hour], unique: true
    add_index :unknown_site_hits, :hour
  end
end
