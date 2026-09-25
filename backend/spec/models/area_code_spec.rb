# frozen_string_literal: true

require "rails_helper"

RSpec.describe AreaCode do
  describe ".region_for" do
    # The case that prompted it (#173): one digit apart, half a country apart.
    it "tells 413 from 414" do
      expect(described_class.region_for("+14132129092")).to eq("Massachusetts")
      expect(described_class.region_for("+14142129092")).to eq("Wisconsin")
    end

    it "names Canadian provinces and the rest of the +1 countries" do
      expect(described_class.region_for("+14165550123")).to eq("Ontario")
      expect(described_class.region_for("+18765550123")).to eq("Jamaica")
    end

    it "says nothing for toll-free codes, which are not a place" do
      expect(described_class.region_for("+18005550123")).to be_nil
    end

    # +44 20 ... is London, not area code 207 (Maine).
    it "says nothing for a number outside +1" do
      expect(described_class.region_for("+442071234567")).to be_nil
    end

    it "says nothing for a blank or malformed number" do
      expect(described_class.region_for(nil)).to be_nil
      expect(described_class.region_for("+1413212909")).to be_nil
    end
  end

  # The table is generated, so pin the few things a bad regeneration would
  # break rather than trusting it wholesale.
  describe "the table" do
    it "covers every US state and DC" do
      expect(described_class::REGIONS.values.uniq & described_class::US_NAMES.values)
        .to include("Alaska", "Hawaii", "Washington, DC", "Wyoming")
    end

    # The lookup indexes by the string it slices out of the number. A YAML key
    # written unquoted would load as an Integer and never match.
    it "keeps area codes as three-digit strings" do
      expect(described_class::REGIONS.keys).to all(match(/\A\d{3}\z/))
    end
  end
end
