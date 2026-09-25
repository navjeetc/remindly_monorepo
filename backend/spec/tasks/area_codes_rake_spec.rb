# frozen_string_literal: true

require "rails_helper"
require "rake"

# The refresh rewrites a table the phone panel reads. What matters is that a
# bad download cannot overwrite a good table with nothing -- the panel would
# quietly stop saying anything for everybody, and nobody would notice.
RSpec.describe "area_codes:refresh", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("area_codes:refresh")
  end

  before { Rake::Task["area_codes:refresh"].reenable }

  let(:table) { Rails.root.join("config/area_codes.yml") }

  def respond_with(body)
    response = instance_double(Net::HTTPOK, body: body, value: nil)
    allow(Net::HTTP).to receive(:get_response).and_return(response)
  end

  def report(rows)
    header = "NPA_ID,type_of_code,USE,LOCATION,COUNTRY,IN_SERVICE"
    "File Date,09/25/2026\n#{header}\n" + rows.map { |npa, use, loc| "#{npa},x,#{use},#{loc},US,Y" }.join("\n") + "\n"
  end

  def refresh = Rake::Task["area_codes:refresh"].invoke

  def expect_table_untouched
    before = table.read
    expect { refresh }.to raise_error(SystemExit).and output(/left as it was/).to_stderr
    expect(table.read).to eq(before)
  end

  it "leaves the table alone when the download is an error page" do
    respond_with("<html><body>Service unavailable</body></html>")

    expect_table_untouched
  end

  it "leaves the table alone when a column it reads has been renamed" do
    respond_with(report([ [ "413", "G", "MA" ] ]).sub("LOCATION", "PLACE"))

    expect_table_untouched
  end

  it "leaves the table alone when the report is implausibly short" do
    respond_with(report([ [ "413", "G", "MA" ], [ "414", "G", "WI" ] ]))

    expect_table_untouched
  end

  it "writes geographic codes, and only those, from a complete report" do
    geographic = (200..699).map { |npa| [ npa.to_s, "G", "MA" ] }
    respond_with(report(geographic + [ [ "800", "N", "NANP AREA" ] ]))

    written = nil
    allow_any_instance_of(Pathname).to receive(:write) { |_path, content| written = content }

    expect { refresh }.to output(/Wrote 500 area codes/).to_stdout

    regions = YAML.safe_load(written)
    expect(regions["413"]).to eq("Massachusetts")
    expect(regions).not_to have_key("800")
  end
end
