require 'rails_helper'

RSpec.describe TimeBlock, type: :model do
  let(:user) { create(:user) }
  
  describe 'validations' do
    it 'is valid when end_time is after start_time' do
      time_block = build(
        :time_block,
        start_time: Time.current,
        end_time: 1.hour.from_now
      )
      
      expect(time_block).to be_valid
    end
    
    it 'is invalid when end_time is before start_time' do
      time_block = build(
        :time_block,
        start_time: Time.current,
        end_time: 1.hour.ago
      )
      
      expect(time_block).not_to be_valid
      expect(time_block.errors[:end_time]).to include('must be after start time')
    end
    
    it 'is invalid when end_time equals start_time' do
      time = Time.current
      time_block = build(
        :time_block,
        start_time: time,
        end_time: time
      )
      
      expect(time_block).not_to be_valid
      expect(time_block.errors[:end_time]).to include('must be after start time')
    end
    
    it 'prevents overlapping blocks for the same user' do
      create(:time_block, user: user, start_time: Time.current, end_time: 2.hours.from_now)
      
      overlapping_block = build(
        :time_block,
        user: user,
        start_time: 1.hour.from_now,
        end_time: 3.hours.from_now
      )
      
      expect(overlapping_block).not_to be_valid
      expect(overlapping_block.errors[:base]).to include('This time block overlaps with an existing block')
    end
    
    it 'allows overlapping blocks for different users' do
      other_user = create(:user)
      create(:time_block, user: user, start_time: Time.current, end_time: 2.hours.from_now)
      
      overlapping_block = build(
        :time_block,
        user: other_user,
        start_time: 1.hour.from_now,
        end_time: 3.hours.from_now
      )
      
      expect(overlapping_block).to be_valid
    end
    
    it 'allows overlapping with inactive blocks' do
      create(:time_block, user: user, start_time: Time.current, end_time: 2.hours.from_now, active: false)
      
      overlapping_block = build(
        :time_block,
        user: user,
        start_time: 1.hour.from_now,
        end_time: 3.hours.from_now
      )
      
      expect(overlapping_block).to be_valid
    end
  end
  
  describe 'scopes' do
    let!(:active_block) { create(:time_block, user: user, active: true, start_time: Time.current, end_time: 1.hour.from_now) }
    let!(:inactive_block) { create(:time_block, user: user, active: false, start_time: 2.hours.from_now, end_time: 3.hours.from_now) }
    let!(:recurring_block) { create(:time_block, user: user, recurring: true, start_time: 4.hours.from_now, end_time: 5.hours.from_now) }
    let!(:one_time_block) { create(:time_block, user: user, recurring: false, start_time: 6.hours.from_now, end_time: 7.hours.from_now) }
    
    describe '.active' do
      it 'returns only active blocks' do
        expect(TimeBlock.active).to include(active_block)
        expect(TimeBlock.active).not_to include(inactive_block)
      end
    end
    
    describe '.recurring' do
      it 'returns only recurring blocks' do
        expect(TimeBlock.recurring).to include(recurring_block)
        expect(TimeBlock.recurring).not_to include(one_time_block)
      end
    end
    
    describe '.one_time' do
      it 'returns only one-time blocks' do
        expect(TimeBlock.one_time).to include(one_time_block)
        expect(TimeBlock.one_time).not_to include(recurring_block)
      end
    end
  end
  
  describe '#blocks_time?' do
    let(:time_block) do
      create(
        :time_block,
        user: user,
        start_time: Time.current,
        end_time: 2.hours.from_now,
        active: true
      )
    end
    
    it 'returns true when time falls within the block' do
      expect(time_block.blocks_time?(1.hour.from_now)).to be true
    end
    
    it 'returns false when time is before the block' do
      expect(time_block.blocks_time?(1.hour.ago)).to be false
    end
    
    it 'returns false when time is after the block' do
      expect(time_block.blocks_time?(3.hours.from_now)).to be false
    end
    
    it 'returns false when block is inactive' do
      time_block.update(active: false)
      expect(time_block.blocks_time?(1.hour.from_now)).to be false
    end
  end
  
  describe '#blocks_range?' do
    let(:time_block) do
      create(
        :time_block,
        user: user,
        start_time: Time.current,
        end_time: 2.hours.from_now,
        active: true
      )
    end
    
    it 'returns true when ranges overlap' do
      expect(time_block.blocks_range?(1.hour.from_now, 3.hours.from_now)).to be true
    end
    
    it 'returns true when range is completely within block' do
      expect(time_block.blocks_range?(30.minutes.from_now, 1.hour.from_now)).to be true
    end
    
    it 'returns true when range completely contains block' do
      expect(time_block.blocks_range?(1.hour.ago, 3.hours.from_now)).to be true
    end
    
    it 'returns false when range is before block' do
      expect(time_block.blocks_range?(2.hours.ago, 1.hour.ago)).to be false
    end
    
    it 'returns false when range is after block' do
      expect(time_block.blocks_range?(3.hours.from_now, 4.hours.from_now)).to be false
    end
    
    it 'returns false when block is inactive' do
      time_block.update(active: false)
      expect(time_block.blocks_range?(1.hour.from_now, 3.hours.from_now)).to be false
    end
  end
end
