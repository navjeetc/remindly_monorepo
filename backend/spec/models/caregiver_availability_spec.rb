require 'rails_helper'

RSpec.describe CaregiverAvailability, type: :model do
  describe 'associations' do
    it { should belong_to(:caregiver).class_name('User') }
  end

  describe 'validations' do
    it { should validate_presence_of(:date) }
    it { should validate_presence_of(:start_time) }
    it { should validate_presence_of(:end_time) }

    it 'validates end_time is after start_time' do
      caregiver = create(:user, role: :caregiver)
      availability = build(:caregiver_availability, 
        caregiver: caregiver,
        start_time: Time.parse('14:00'),
        end_time: Time.parse('10:00')
      )
      
      expect(availability).not_to be_valid
      expect(availability.errors[:end_time]).to include('must be after start time')
    end

    it 'is valid when end_time is after start_time' do
      caregiver = create(:user, role: :caregiver)
      availability = build(:caregiver_availability,
        caregiver: caregiver,
        start_time: Time.parse('10:00'),
        end_time: Time.parse('14:00')
      )
      
      expect(availability).to be_valid
    end
  end

  describe 'scopes' do
    let(:caregiver) { create(:user, role: :caregiver) }
    let!(:today_availability) { create(:caregiver_availability, caregiver: caregiver, date: Date.current) }
    let!(:future_availability) { create(:caregiver_availability, caregiver: caregiver, date: 1.week.from_now) }
    let!(:past_availability) { create(:caregiver_availability, caregiver: caregiver, date: 1.week.ago) }

    it 'returns availability for a specific caregiver' do
      other_caregiver = create(:user, role: :caregiver)
      other_availability = create(:caregiver_availability, caregiver: other_caregiver)
      
      expect(CaregiverAvailability.for_caregiver(caregiver.id)).to include(today_availability)
      expect(CaregiverAvailability.for_caregiver(caregiver.id)).not_to include(other_availability)
    end

    it 'returns availability for a specific date' do
      expect(CaregiverAvailability.for_date(Date.current)).to include(today_availability)
      expect(CaregiverAvailability.for_date(Date.current)).not_to include(future_availability)
    end

    it 'returns upcoming availability' do
      expect(CaregiverAvailability.upcoming).to include(today_availability, future_availability)
      expect(CaregiverAvailability.upcoming).not_to include(past_availability)
    end
  end
end
