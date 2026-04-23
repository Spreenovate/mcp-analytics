class CreateUsageCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_counters do |t|
      t.string :site_id, null: false
      t.date :month, null: false
      t.bigint :hit_count, null: false, default: 0
      t.timestamps
    end

    add_index :usage_counters, [:site_id, :month], unique: true
  end
end
