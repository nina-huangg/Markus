class RemoveInvalidOverrideFromAssignment < ActiveRecord::Migration[7.0]
  def change
    remove_column :assignment_properties, :invalid_override
  end
end
