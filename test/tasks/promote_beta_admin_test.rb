require "test_helper"
require "rake"

class PromoteBetaAdminTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:promote_beta_admin")
    @task = Rake::Task["users:promote_beta_admin"]
    @target = User.create!(
      first_name: "Sergi",
      last_name: "Carpenter",
      email_address: "sergiescarpenter@gmail.com",
      password: SecureRandom.urlsafe_base64(32),
      email_verified_at: Time.current
    )
    @target.identities.create!(provider: "google", uid: "verified-google-account")
  end

  test "promotes only the intended account and is idempotent" do
    other_user = User.create!(
      first_name: "Regular",
      last_name: "User",
      email_address: "regular-user@example.com",
      password: SecureRandom.urlsafe_base64(32)
    )

    invoke_task
    invoke_task

    assert_equal [ @target.id ], User.where(admin: true).pluck(:id)
    assert_not other_user.reload.admin?
  end

  test "refuses to change accounts when another administrator exists" do
    other_admin = User.create!(
      first_name: "Other",
      last_name: "Admin",
      email_address: "other-admin@example.com",
      password: SecureRandom.urlsafe_base64(32),
      admin: true
    )

    assert_raises(RuntimeError) { invoke_task }

    assert_not @target.reload.admin?
    assert other_admin.reload.admin?
    assert_equal [ other_admin.id ], User.where(admin: true).pluck(:id)
  end

  test "refuses to promote an account without verified email" do
    @target.update!(email_verified_at: nil)

    error = assert_raises(RuntimeError) { invoke_task }

    assert_equal "Admin account must have a verified email", error.message
    assert_not @target.reload.admin?
  end

  private

  def invoke_task
    @task.reenable
    @task.invoke
  end
end
