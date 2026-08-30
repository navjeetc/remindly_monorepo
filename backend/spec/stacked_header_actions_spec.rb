require "rails_helper"

# A header that stacks is only half the fix. Two of the headers this branch
# changed to flex-col still held their buttons in a `flex space-x-*` group,
# which cannot wrap — so at the largest text size on a phone the heading
# stacked neatly and the buttons underneath it ran off the right edge anyway.
#
# Asserted against the templates rather than a rendered page, in the same spirit
# as public_assets_spec: the rule is a convention about two classes belonging
# together, and it should hold for every stacked header in the app, including
# ones behind feature flags or roles a request spec would have to set up to
# reach.
RSpec.describe "action groups inside stacked headers" do
  STACKED_HEADER = /flex flex-col gap-4 sm:flex-row/
  NON_WRAPPING = /class="flex space-x-/

  # The action group sits within a few lines of the heading it belongs to;
  # anything further down the page is a different container.
  LINES_BELOW = 6

  def offenders
    Dir[Rails.root.join("app/views/**/*.erb")].sort.flat_map do |path|
      lines = File.readlines(path)

      lines.each_index.filter_map do |i|
        next unless lines[i].match?(STACKED_HEADER)

        below = lines[(i + 1), LINES_BELOW] || []
        hit = below.index { |line| line.match?(NON_WRAPPING) }
        "#{path.sub("#{Rails.root}/", "")}:#{i + hit + 2}" if hit
      end
    end
  end

  it "lets the buttons wrap wherever the heading does" do
    found = offenders

    expect(found).to be_empty,
      "these headings stack but their buttons cannot, so the buttons still " \
      "overflow at the largest text size. Use flex-wrap and a gap rather than " \
      "space-x-*:\n  #{found.join("\n  ")}"
  end
end
