class AddContactPreferenceToLeads < ActiveRecord::Migration[8.1]
  def change
    add_column :leads, :contact_preference, :string
  end
end
