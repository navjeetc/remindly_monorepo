require "test_helper"

class CaregiverAvailabilityTest < ActiveSupport::TestCase
  def setup
    @caregiver = users(:caregiver_one)
    @date = Date.current + 1.day
  end

  test "should not allow overlapping availability - new slot starts before existing ends" do
    # Create first availability: 9am-12pm
    existing = CaregiverAvailability.create!(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("12:00")
    )

    # Try to create overlapping: 10am-2pm (starts before existing ends)
    overlapping = CaregiverAvailability.new(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("10:00"),
      end_time: Time.parse("14:00")
    )

    assert_not overlapping.valid?
    assert_includes overlapping.errors[:base], "This time slot overlaps with existing availability"
  end

  test "should not allow overlapping availability - new slot extends past existing" do
    # Create first availability: 9am-12pm
    existing = CaregiverAvailability.create!(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("12:00")
    )

    # Try to create overlapping: 8am-10am (extends past existing start)
    overlapping = CaregiverAvailability.new(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("08:00"),
      end_time: Time.parse("10:00")
    )

    assert_not overlapping.valid?
    assert_includes overlapping.errors[:base], "This time slot overlaps with existing availability"
  end

  test "should not allow overlapping availability - new slot completely contains existing" do
    # Create first availability: 10am-12pm
    existing = CaregiverAvailability.create!(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("10:00"),
      end_time: Time.parse("12:00")
    )

    # Try to create overlapping: 9am-2pm (completely contains existing)
    overlapping = CaregiverAvailability.new(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("14:00")
    )

    assert_not overlapping.valid?
    assert_includes overlapping.errors[:base], "This time slot overlaps with existing availability"
  end

  test "should allow non-overlapping availability on same date" do
    # Create first availability: 9am-12pm
    existing = CaregiverAvailability.create!(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("12:00")
    )

    # Create non-overlapping: 2pm-5pm
    non_overlapping = CaregiverAvailability.new(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("14:00"),
      end_time: Time.parse("17:00")
    )

    assert non_overlapping.valid?
  end

  test "should allow same time slot on different dates" do
    # Create first availability: 9am-12pm on date1
    existing = CaregiverAvailability.create!(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("12:00")
    )

    # Create same time on different date
    different_date = CaregiverAvailability.new(
      caregiver: @caregiver,
      date: @date + 1.day,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("12:00")
    )

    assert different_date.valid?
  end

  test "should allow updating existing availability without overlap error" do
    availability = CaregiverAvailability.create!(
      caregiver: @caregiver,
      date: @date,
      start_time: Time.parse("09:00"),
      end_time: Time.parse("12:00")
    )

    # Update the same record
    availability.notes = "Updated notes"
    assert availability.valid?
  end
end
