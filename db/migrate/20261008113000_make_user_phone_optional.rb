class MakeUserPhoneOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :phone, from: "", to: nil
    change_column_null :users, :phone, true
  end
end
