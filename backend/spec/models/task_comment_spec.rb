require 'rails_helper'

RSpec.describe TaskComment, type: :model do
  describe 'associations' do
    it { should belong_to(:task) }
    it { should belong_to(:user) }
  end

  describe 'validations' do
    it { should validate_presence_of(:content) }
    it { should validate_length_of(:content).is_at_least(1).is_at_most(5000) }
  end

  describe 'scopes' do
    let(:task) { create(:task) }
    let!(:old_comment) { create(:task_comment, task: task, created_at: 2.days.ago) }
    let!(:new_comment) { create(:task_comment, task: task, created_at: 1.day.ago) }

    it 'returns comments in reverse chronological order' do
      expect(TaskComment.recent.first).to eq(new_comment)
      expect(TaskComment.recent.last).to eq(old_comment)
    end

    it 'returns comments for a specific task' do
      other_task = create(:task)
      other_comment = create(:task_comment, task: other_task)
      
      expect(TaskComment.for_task(task.id)).to include(old_comment, new_comment)
      expect(TaskComment.for_task(task.id)).not_to include(other_comment)
    end
  end
end
