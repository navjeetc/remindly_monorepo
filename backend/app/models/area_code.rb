# frozen_string_literal: true

# Which state, province or country a North American phone number's area code
# belongs to, from NANPA's own list (config/area_codes.yml).
#
# Shown to a caregiver as information beside the number they saved, never as a
# check on it. A caregiver typed 414 for 413 and three consent calls rang a
# stranger in Wisconsin while her mother waited in Massachusetts (#173); the
# digits were on the screen the whole time and did not say where they pointed.
# But an area code says where a number was issued, not where its owner is --
# people keep their mobile numbers when they move -- so it informs rather than
# warns.
class AreaCode
  REGIONS = YAML.load_file(Rails.root.join("config/area_codes.yml")).freeze

  # NANPA's LOCATION column: postal codes for the US, names in capitals for
  # everywhere else, and a few spellings of its own.
  US_NAMES = {
    "AK" => "Alaska", "AL" => "Alabama", "AR" => "Arkansas", "AS" => "American Samoa",
    "AZ" => "Arizona", "CA" => "California", "CNMI" => "Northern Mariana Islands",
    "CO" => "Colorado", "CT" => "Connecticut", "DC" => "Washington, DC", "DE" => "Delaware",
    "FL" => "Florida", "GA" => "Georgia", "GU" => "Guam", "HI" => "Hawaii", "IA" => "Iowa",
    "ID" => "Idaho", "IL" => "Illinois", "IN" => "Indiana", "KS" => "Kansas",
    "KY" => "Kentucky", "LA" => "Louisiana", "MA" => "Massachusetts", "MD" => "Maryland",
    "ME" => "Maine", "MI" => "Michigan", "MN" => "Minnesota", "MO" => "Missouri",
    "MS" => "Mississippi", "MT" => "Montana", "NC" => "North Carolina", "ND" => "North Dakota",
    "NE" => "Nebraska", "NH" => "New Hampshire", "NJ" => "New Jersey", "NM" => "New Mexico",
    "NV" => "Nevada", "NY" => "New York", "OH" => "Ohio", "OK" => "Oklahoma", "OR" => "Oregon",
    "PA" => "Pennsylvania", "PR" => "Puerto Rico", "RI" => "Rhode Island",
    "SC" => "South Carolina", "SD" => "South Dakota", "TN" => "Tennessee", "TX" => "Texas",
    "UT" => "Utah", "VA" => "Virginia", "VI" => "US Virgin Islands", "VT" => "Vermont",
    "WA" => "Washington", "WI" => "Wisconsin", "WV" => "West Virginia", "WY" => "Wyoming"
  }.freeze

  SPELLED_OUT = {
    "ANTIGUA/BARBUDA" => "Antigua and Barbuda",
    "NEWFOUNDLAND AND LABRADOR" => "Newfoundland and Labrador",
    "NORTHWEST TERRITORIES -YUKON - NUNAVUT" => "Northwest Territories, Yukon and Nunavut",
    "NOVA SCOTIA - PRINCE EDWARD ISLAND" => "Nova Scotia and Prince Edward Island",
    "ST. KITTS & NEVIS" => "St. Kitts and Nevis",
    "ST. LUCIA" => "St. Lucia",
    "ST. VINCENT & GRENADINES" => "St. Vincent and the Grenadines",
    "TRINIDAD & TOBAGO" => "Trinidad and Tobago",
    "TURKS & CAICOS ISLANDS" => "Turks and Caicos Islands"
  }.freeze

  # "413" for +14132129092; nil for anything that is not a +1 number, where the
  # first digits after the country code are not an area code at all.
  def self.for(phone)
    phone.to_s[/\A\+1(\d{3})\d{7}\z/, 1]
  end

  # "Massachusetts" for +14132129092; nil when there is nothing true to say.
  def self.region_for(phone)
    REGIONS[self.for(phone)]
  end

  # Used by area_codes:refresh to turn NANPA's LOCATION into a readable name.
  def self.region_name(location)
    US_NAMES[location] || SPELLED_OUT[location] || location.titleize
  end
end
