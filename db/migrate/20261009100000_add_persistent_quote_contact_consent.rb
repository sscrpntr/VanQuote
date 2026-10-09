class AddPersistentQuoteContactConsent < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :operational_email_consent, :boolean, default: false, null: false
    add_column :users, :operational_email_consent_at, :datetime
    add_column :users, :operational_email_consent_text_version, :string
    add_column :users, :operational_email_consent_purpose, :string
    add_column :users, :terms_accepted_at, :datetime
    add_column :users, :terms_version, :string

    add_column :quotes, :contact_email, :string

    create_table :operational_email_consent_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.string :text_version
      t.string :purpose, null: false
      t.text :consent_text
      t.datetime :occurred_at, null: false
      t.timestamps
    end
  end
end
