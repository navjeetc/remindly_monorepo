# frozen_string_literal: true

require "rails_helper"

# Telnyx's outbound profile allows only the United States and Canada. A number
# anywhere else used to save without a word and then fail at "Call and ask",
# telling the caregiver to try again or claiming a call that never rang. It is
# now refused when typed, with the reason.
RSpec.describe "Saving a number Remindly cannot call", type: :model do
  subject(:senior) { create(:user, :senior, name: "Mom") }

  def refusal_for(phone)
    senior.phone = phone
    senior.valid?
    senior.errors.full_messages.to_sentence
  end

  it "accepts numbers in the United States and Canada" do
    {
      "+14132129092" => "Massachusetts",
      "+12025550123" => "Washington, DC",
      "+14165550123" => "Ontario",
      "+16045550123" => "British Columbia"
    }.each do |phone, region|
      expect(AreaCode.region_for(phone)).to eq(region)
      expect(refusal_for(phone)).to be_empty, "#{phone} (#{region}) was refused"
    end
  end

  it "refuses a number outside +1, saying why" do
    expect(refusal_for("+44 20 7123 4567"))
      .to eq("Remindly can only call numbers in the US and Canada for now, and +442071234567 is outside them.")
    expect(senior.reload.phone).not_to eq("+442071234567")
  end

  # +1 is wider than the US and Canada, and Telnyx bills and refuses the rest
  # of it as international.
  it "refuses a +1 number in the Caribbean, naming where it is" do
    expect(refusal_for("+1 876 555 0123"))
      .to eq("Remindly can only call numbers in the US and Canada for now, and +18765550123 is in Jamaica.")
    expect(refusal_for("+14415550123")).to include("is in Bermuda")
  end

  # Not confirmed to count as the United States at Telnyx; refused until a
  # live call to one has rung.
  it "refuses the US territories for now" do
    expect(refusal_for("+17875550123")).to include("is in Puerto Rico")
  end

  # Refusing a real US number would be worse than the rare call Telnyx declines.
  it "lets through a +1 area code the NANPA list does not name" do
    expect(AreaCode.region_for("+15551234567")).to be_nil
    expect(refusal_for("+15551234567")).to be_empty
  end

  it "tells the caregiver about a malformed number, and only that" do
    expect(refusal_for("12345")).to eq("Phone must be a valid E.164 number like +15551234567")
  end

  # A row saved before the rule must stay saveable for an unrelated edit.
  it "does not block other changes to a senior whose saved number predates the rule" do
    senior.update_column(:phone, "+442071234567")

    expect(senior.reload.update(name: "Mum")).to be(true)
  end
end
