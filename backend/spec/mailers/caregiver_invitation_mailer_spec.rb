require 'rails_helper'

RSpec.describe CaregiverInvitationMailer, type: :mailer do
  describe '#invitation_email' do
    let(:senior) { create(:user, role: :senior, email: 'senior@example.com', name: 'John Senior') }
    let(:caregiver) { create(:user, role: :caregiver, email: 'caregiver@example.com', name: 'Jane Caregiver') }
    let(:inviter) { create(:user, role: :caregiver, email: 'inviter@example.com', name: 'Bob Inviter') }
    let(:mail) { CaregiverInvitationMailer.invitation_email(caregiver: caregiver, senior: senior, inviter: inviter) }

    it 'renders the subject' do
      expect(mail.subject).to eq("You've been invited to help care for John Senior")
    end

    it 'sends to the caregiver email' do
      expect(mail.to).to eq([caregiver.email])
    end

    it 'sends from the default mailer address' do
      from_address = Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")
      expect(mail.from).to eq([from_address])
    end

    it 'includes the inviter name in the body' do
      expect(mail.body.encoded).to include(inviter.display_name)
    end

    it 'includes the senior name in the body' do
      expect(mail.body.encoded).to include(senior.display_name)
    end

    it 'includes the caregiver email in the body' do
      expect(mail.body.encoded).to include(caregiver.email)
    end

    it 'includes the login URL in the body' do
      expect(mail.body.encoded).to include('/login')
    end

    it 'includes information about what caregivers can do' do
      expect(mail.body.encoded).to include('View and manage tasks')
    end
  end
end
