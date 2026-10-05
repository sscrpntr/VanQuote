class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.references :quote, null: false, foreign_key: true
      t.string :email, null: false
      t.boolean :consent_given, null: false
      t.datetime :consent_at, null: false
      t.string :status, null: false

      t.timestamps
    end
  end
end
