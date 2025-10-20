require 'rails_helper'

RSpec.describe Task, type: :model do
  describe 'associations' do
    it { should belong_to(:senior).class_name('User') }
    it { should belong_to(:assigned_to).class_name('User').optional }
    it { should belong_to(:created_by).class_name('User') }
    it { should have_many(:task_comments).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:task_type) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:priority) }
    it { should validate_presence_of(:scheduled_at) }
  end

  describe 'enums' do
    it { should define_enum_for(:task_type).with_values(appointment: 0, errand: 1, activity: 2, household: 3, transportation: 4, other: 5) }
    it { should define_enum_for(:status).with_values(pending: 0, assigned: 1, in_progress: 2, completed: 3, cancelled: 4) }
    it { should define_enum_for(:priority).with_values(low: 0, medium: 1, high: 2, urgent: 3) }
  end

  describe 'scopes' do
    let(:senior) { create(:user, role: :senior) }
    let(:caregiver) { create(:user, role: :caregiver) }
    let!(:upcoming_task) { create(:task, senior: senior, scheduled_at: 1.day.from_now) }
    let!(:past_task) { create(:task, senior: senior, scheduled_at: 1.day.ago) }
    let!(:assigned_task) { create(:task, senior: senior, assigned_to: caregiver) }
    let!(:unassigned_task) { create(:task, senior: senior, assigned_to: nil) }

    it 'returns upcoming tasks' do
      expect(Task.upcoming).to include(upcoming_task)
      expect(Task.upcoming).not_to include(past_task)
    end

    it 'returns past tasks' do
      expect(Task.past).to include(past_task)
      expect(Task.past).not_to include(upcoming_task)
    end

    it 'returns tasks for a specific senior' do
      other_senior = create(:user, role: :senior)
      other_task = create(:task, senior: other_senior)
      
      expect(Task.for_senior(senior.id)).to include(upcoming_task, past_task)
      expect(Task.for_senior(senior.id)).not_to include(other_task)
    end

    it 'returns assigned tasks for a user' do
      expect(Task.assigned_to_user(caregiver.id)).to include(assigned_task)
      expect(Task.assigned_to_user(caregiver.id)).not_to include(unassigned_task)
    end

    it 'returns unassigned tasks' do
      expect(Task.unassigned).to include(unassigned_task)
      expect(Task.unassigned).not_to include(assigned_task)
    end
  end

  describe 'callbacks' do
    let(:senior) { create(:user, role: :senior) }
    let(:caregiver) { create(:user, role: :caregiver) }
    let(:creator) { create(:user, role: :caregiver) }

    describe '#update_status_on_assignment' do
      it 'changes status to assigned when a caregiver is assigned' do
        task = create(:task, senior: senior, created_by: creator, status: :pending, assigned_to: nil)
        task.update(assigned_to: caregiver)
        
        expect(task.status).to eq('assigned')
      end

      it 'does not change status if already not pending' do
        task = create(:task, senior: senior, created_by: creator, status: :in_progress, assigned_to: caregiver)
        new_caregiver = create(:user, role: :caregiver)
        task.update(assigned_to: new_caregiver)
        
        expect(task.status).to eq('in_progress')
      end
    end

    describe '#set_completed_at' do
      it 'sets completed_at when status changes to completed' do
        task = create(:task, senior: senior, created_by: creator, status: :in_progress)
        task.update(status: :completed)
        
        expect(task.completed_at).to be_present
      end

      it 'clears completed_at when status changes from completed' do
        task = create(:task, senior: senior, created_by: creator, status: :completed, completed_at: Time.current)
        task.update(status: :in_progress)
        
        expect(task.completed_at).to be_nil
      end
    end
  end
end
