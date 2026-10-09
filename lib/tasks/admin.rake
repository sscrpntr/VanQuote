namespace :users do
  desc "Make the verified Google account sergiescarpenter@gmail.com the sole administrator"
  task promote_beta_admin: :environment do
    email = "sergiescarpenter@gmail.com"
    user = User.find_by!(email_address: email)
    raise "Admin account must have a verified email" unless user.email_verified?
    raise "Admin account must be linked to Google" unless user.identities.exists?(provider: "google")

    User.transaction do
      other_admin_exists = User.where(admin: true).where.not(id: user.id).exists?
      raise "Another administrator exists; refusing to change another account" if other_admin_exists

      user.update!(admin: true) unless user.admin?
    end

    puts "Sole admin configured for #{user.email_address}"
  rescue ActiveRecord::RecordNotUnique
    raise "Another administrator was promoted concurrently; the database rejected this promotion"
  end
end
