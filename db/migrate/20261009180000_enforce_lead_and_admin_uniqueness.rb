class EnforceLeadAndAdminUniqueness < ActiveRecord::Migration[8.1]
  def change
    add_index :leads, :quote_id, unique: true, name: "idx_leads_quote_uidx"
    add_index :users, :admin, unique: true, where: "admin = true", name: "idx_users_single_admin_uidx"
  end
end
