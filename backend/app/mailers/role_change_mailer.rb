class RoleChangeMailer < ApplicationMailer
  def role_updated(user:, old_role:, new_role:, changed_by:)
    @user = user
    @old_role = old_role || "none"
    @new_role = new_role || "none"
    @changed_by = changed_by
    
    mail(
      to: @user.email,
      subject: "Your Remindly account role has been updated"
    )
  end
end
