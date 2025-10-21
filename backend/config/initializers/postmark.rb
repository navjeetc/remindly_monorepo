# Postmark configuration
# This initializer ensures Postmark is properly configured for all environments

if Rails.env.production?
  ActionMailer::Base.delivery_method = :postmark
  ActionMailer::Base.postmark_settings = {
    api_token: Rails.application.credentials.postmark_api_token
  }
end
