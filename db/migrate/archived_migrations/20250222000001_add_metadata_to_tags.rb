class AddMetadataToTags < ActiveRecord::Migration[8.0]
  def change
    add_column :tags, :metadata, :jsonb, default: {}
    add_index :tags, :metadata, using: :gin
    add_index :tags, :category
  end
end
