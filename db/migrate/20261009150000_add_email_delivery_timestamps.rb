class AddEmailDeliveryTimestamps < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :result_email_sent_at, :datetime
    add_column :leads, :admin_notification_sent_at, :datetime
  end
end
