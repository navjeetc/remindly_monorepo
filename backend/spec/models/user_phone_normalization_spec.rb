# frozen_string_literal: true

require "rails_helper"

# E.164 is what Telnyx dials and what the column holds. It is not how anybody in
# the United States or Canada writes a telephone number, and until this the field
# refused every shape they would naturally type -- so a caregiver setting up a
# parent had to learn what E.164 was before Remindly would keep the number.
RSpec.describe "Typing a phone number the way it is written", type: :model do
  subject(:senior) { create(:user, :senior, name: "Mom") }

  it "adds +1 to ten digits" do
    senior.update!(phone: "414-212-9092")

    expect(senior.reload.phone).to eq("+14142129092")
  end

  it "accepts the shapes people actually write" do
    [ "(414) 212-9092", "414.212.9092", "4142129092", " 414 212 9092 " ].each do |typed|
      senior.update!(phone: typed)

      expect(senior.reload.phone).to eq("+14142129092")
    end
  end

  it "accepts a leading 1 without a plus" do
    senior.update!(phone: "1 414 212 9092")

    expect(senior.reload.phone).to eq("+14142129092")
  end

  # The country code stays typeable. Assuming +1 for a number that says +44 is
  # how a call goes to a stranger.
  it "leaves a number that names its own country code alone" do
    senior.update!(phone: "+44 20 7123 4567")

    expect(senior.reload.phone).to eq("+442071234567")
  end

  # Normalising is not the same as accepting anything. Seven digits is a local
  # number with no area code, and guessing one would dial somebody.
  it "still refuses a number it cannot make sense of" do
    senior.phone = "212-9092"

    expect(senior).not_to be_valid
    expect(senior.errors[:phone].join).to match(/E\.164/)
  end

  # The consent columns are cleared whenever the number changes. Retyping the
  # same number in a different shape is not a change, and treating it as one
  # would switch off calls somebody had already agreed to.
  it "does not discard consent when the same number is retyped differently" do
    senior.update!(phone: "+14142129092")
    senior.update_columns(phone_verified_at: Time.current, call_consent_at: Time.current,
                          call_reminders_enabled: true)

    senior.reload.update!(phone: "(414) 212-9092")

    expect(senior.reload).to be_callable_by_phone
  end
end
