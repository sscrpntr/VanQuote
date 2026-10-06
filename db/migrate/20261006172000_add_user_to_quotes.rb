class AddUserToQuotes < ActiveRecord::Migration[8.0]
  def change
    add_reference :quotes,
                  :user,
                  foreign_key: true,
                  null: true
  end
end
