class AddIndexesToContentItem < ActiveRecord::Migration[5.0]
  disable_ddl_transaction!

  def change
    add_index :content_items, [:content_id, :state, :locale], algorithm: :concurrently
    add_index :content_items, [:state, :base_path], algorithm: :concurrently
  end
end
