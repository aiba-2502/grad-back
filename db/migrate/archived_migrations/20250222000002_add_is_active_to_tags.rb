class AddIsActiveToTags < ActiveRecord::Migration[8.0]
  def change
    add_column :tags, :is_active, :boolean, default: true
    add_index :tags, :is_active
    add_index :tags, [ :category, :is_active ]
  end
end
