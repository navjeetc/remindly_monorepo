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
    # Note: scheduled_at is optional for open-ended tasks

    describe 'recurring task validations' do
      let(:senior) { create(:user, role: :senior) }
      let(:creator) { create(:user, role: :caregiver) }

      it 'requires tz when rrule is present' do
        task = build(:task, senior: senior, created_by: creator, rrule: 'FREQ=DAILY', tz: nil, start_time: Time.current)
        expect(task).not_to be_valid
        expect(task.errors[:tz]).to include("can't be blank")
      end

      it 'requires start_time when rrule is present' do
        task = build(:task, senior: senior, created_by: creator, rrule: 'FREQ=DAILY', tz: 'America/New_York', start_time: nil)
        expect(task).not_to be_valid
        expect(task.errors[:start_time]).to include("can't be blank")
      end

      it 'validates timezone is valid when rrule is present' do
        task = build(:task, senior: senior, created_by: creator, rrule: 'FREQ=DAILY', tz: 'Invalid/Timezone', start_time: Time.current)
        expect(task).not_to be_valid
        expect(task.errors[:tz]).to include('is not a valid timezone')
      end

      it 'allows valid recurring task' do
        task = build(:task, senior: senior, created_by: creator, rrule: 'FREQ=DAILY', tz: 'America/New_York', start_time: Time.current)
        expect(task).to be_valid
      end

      it 'does not require tz/start_time when rrule is not present' do
        task = build(:task, senior: senior, created_by: creator, rrule: nil, tz: nil, start_time: nil)
        expect(task).to be_valid
      end
    end
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

    describe 'open-ended vs scheduled' do
      let!(:open_ended_task) { create(:task, senior: senior, scheduled_at: nil) }
      let!(:scheduled_task) { create(:task, senior: senior, scheduled_at: 1.day.from_now) }

      it 'returns open-ended tasks (no scheduled_at)' do
        expect(Task.open_ended).to include(open_ended_task)
        expect(Task.open_ended).not_to include(scheduled_task)
      end

      it 'returns scheduled tasks (has scheduled_at)' do
        expect(Task.scheduled).to include(scheduled_task)
        expect(Task.scheduled).not_to include(open_ended_task)
      end
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

  describe 'recurring task instance management' do
    let(:senior) { create(:user, role: :senior) }
    let(:creator) { create(:user, role: :caregiver) }

    it 'cleans up future instances when recurrence is removed' do
      # Create a recurring task
      task = create(:task,
        senior: senior,
        created_by: creator,
        rrule: 'FREQ=DAILY',
        tz: 'America/New_York',
        start_time: Time.current
      )

      # Create future instances
      3.times do |i|
        create(:task,
          senior: senior,
          created_by: creator,
          parent_task: task,
          scheduled_at: (i + 1).days.from_now,
          status: :pending
        )
      end

      expect(task.child_tasks.count).to eq(3)

      # Simulate controller behavior: check if was recurring, then update
      was_recurring = task.recurring_template?
      task.update!(rrule: nil, tz: nil, start_time: nil)

      # If was recurring but no longer is, clean up
      if was_recurring && !task.recurring_template?
        task.child_tasks.upcoming.where(status: :pending).destroy_all
      end

      expect(task.child_tasks.upcoming.where(status: :pending).count).to eq(0)
    end

    it 'preserves completed instances when recurrence is removed' do
      # Create a recurring task
      task = create(:task,
        senior: senior,
        created_by: creator,
        rrule: 'FREQ=DAILY',
        tz: 'America/New_York',
        start_time: Time.current
      )

      # Create a completed instance and a pending instance
      completed_instance = create(:task,
        senior: senior,
        created_by: creator,
        parent_task: task,
        scheduled_at: 1.day.ago,
        status: :completed
      )

      pending_instance = create(:task,
        senior: senior,
        created_by: creator,
        parent_task: task,
        scheduled_at: 1.day.from_now,
        status: :pending
      )

      # Remove recurrence
      was_recurring = task.recurring_template?
      task.update!(rrule: nil)

      # Clean up only pending future instances
      if was_recurring && !task.recurring_template?
        task.child_tasks.upcoming.where(status: :pending).destroy_all
      end

      # Completed instance should remain
      expect(Task.exists?(completed_instance.id)).to be true
      # Pending future instance should be removed
      expect(Task.exists?(pending_instance.id)).to be false
    end
  end
end
