class AddLeadConsentWithdrawalTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :leads, :consent_basis, :string
    add_column :leads, :consent_withdrawn_at, :datetime
  end
end
