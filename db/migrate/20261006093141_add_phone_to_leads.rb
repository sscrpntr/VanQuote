class AddPhoneToLeads < ActiveRecord::Migration[7.0]
  def change
    add_column :leads, :phone, :string
  end
end
