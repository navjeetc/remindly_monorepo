class SchedulingIntegration < ApplicationRecord
  belongs_to :user
  belongs_to :senior, class_name: "User", optional: true
  has_many :tasks, dependent: :nullify

  enum :provider, {
    acuity: 0,
    calendly: 1
  }, prefix: true

  enum :status, {
    active: 0,
    inactive: 1,
    error: 2
  }, prefix: true

  # Encrypted credentials
  # Skip encryption in test environment if credentials are not set up
  if Rails.application.credentials.active_record_encryption.present?
    encrypts :api_key, deterministic: false
    encrypts :api_secret, deterministic: false
    encrypts :access_token, deterministic: false
  end

  validates :provider, presence: true
  validates :status, presence: true
  validates :provider_user_id, presence: true
  validates :user, presence: true

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :sync_enabled, -> { where(sync_enabled: true) }
  scope :needs_sync, -> { 
    active.sync_enabled.where("last_synced_at IS NULL OR last_synced_at < ?", 1.hour.ago) 
  }

  # Check if integration is healthy
  def healthy?
    status_active? && provider_user_id.present? && credentials_present?
  end

  # Check if credentials are present
  def credentials_present?
    case provider
    when "acuity"
      api_key.present?
    when "calendly"
      access_token.present?
    else
      false
    end
  end

  # Mark as error with message
  def mark_error!(message)
    update!(
      status: :error,
      settings: settings.merge(last_error: message, last_error_at: Time.current)
    )
  end

  # Mark as active
  def mark_active!
    update!(status: :active)
  end

  # Update last sync time
  def mark_synced!
    update!(last_synced_at: Time.current)
  end
end
