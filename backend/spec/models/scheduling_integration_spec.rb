require 'rails_helper'

RSpec.describe SchedulingIntegration, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:senior).class_name('User').optional }
    it { should have_many(:tasks).dependent(:nullify) }
  end

  describe 'validations' do
    it { should validate_presence_of(:provider) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:provider_user_id) }
    it { should validate_presence_of(:user) }
  end

  describe 'enums' do
    it { should define_enum_for(:provider).with_values(acuity: 0, calendly: 1).with_prefix(:provider) }
    it { should define_enum_for(:status).with_values(active: 0, inactive: 1, error: 2).with_prefix(:status) }
  end

  describe 'scopes' do
    let!(:active_integration) { create(:scheduling_integration, status: :active) }
    let!(:inactive_integration) { create(:scheduling_integration, status: :inactive) }

    it 'returns active integrations' do
      expect(SchedulingIntegration.active).to include(active_integration)
      expect(SchedulingIntegration.active).not_to include(inactive_integration)
    end
  end

  describe '#healthy?' do
    let(:integration) { build(:scheduling_integration, provider: :acuity, status: :active, api_key: 'test_key') }

    it 'returns true when integration is active and has credentials' do
      expect(integration.healthy?).to be true
    end

    it 'returns false when status is not active' do
      integration.status = :inactive
      expect(integration.healthy?).to be false
    end

    it 'returns false when credentials are missing' do
      integration.api_key = nil
      expect(integration.healthy?).to be false
    end
  end

  describe '#credentials_present?' do
    context 'for Acuity provider' do
      let(:integration) { build(:scheduling_integration, provider: :acuity) }

      it 'returns true when api_key is present' do
        integration.api_key = 'test_key'
        expect(integration.credentials_present?).to be true
      end

      it 'returns false when api_key is missing' do
        integration.api_key = nil
        expect(integration.credentials_present?).to be false
      end
    end

    context 'for Calendly provider' do
      let(:integration) { build(:scheduling_integration, provider: :calendly) }

      it 'returns true when access_token is present' do
        integration.access_token = 'test_token'
        expect(integration.credentials_present?).to be true
      end

      it 'returns false when access_token is missing' do
        integration.access_token = nil
        expect(integration.credentials_present?).to be false
      end
    end
  end

  describe '#mark_error!' do
    let(:integration) { create(:scheduling_integration, status: :active) }

    it 'marks integration as error with message' do
      integration.mark_error!('Test error')
      
      expect(integration.status).to eq('error')
      expect(integration.settings['last_error']).to eq('Test error')
      expect(integration.settings['last_error_at']).to be_present
    end
  end

  describe '#mark_synced!' do
    let(:integration) { create(:scheduling_integration, last_synced_at: nil) }

    it 'updates last_synced_at timestamp' do
      expect {
        integration.mark_synced!
      }.to change { integration.last_synced_at }.from(nil)
    end
  end
end
