# frozen_string_literal: true

require "rails_helper"

# A header that stacks is only half the fix. Several headers this branch changed
# to flex-col still held their controls in a `flex space-x-*` group, which
# cannot wrap — so at the largest text size the heading stacked neatly and the
# buttons underneath it still ran off the right edge, which is the bug the
# branch exists to fix. `space-x-*` adds no vertical spacing either, so a group
# that does wrap without a gap comes out touching.
#
# Asserted against the templates rather than a rendered page, in the same spirit
# as public_assets_spec: the rule is a convention about classes belonging
# together, and it should hold for every stacked header in the app, including
# ones behind feature flags or roles a request spec would have to set up to
# reach.
RSpec.describe "action groups inside stacked headers" do
  STACKED_HEADER = /flex flex-col gap-4 sm:flex-row/

  # Any flex row spacing its children with space-x-*, however many utilities sit
  # between the two. The first version of this spec anchored `flex` directly to
  # `space-x-`, so `flex items-center space-x-3` — just as unable to wrap — went
  # unnoticed.
  ACTION_GROUP = /class="[^"]*\bflex\b[^"]*\bspace-x-/
  WRAPS = /\bflex-wrap\b/

  # The group belongs to the header when it is nested inside it, which the
  # indentation tells us. The first version counted six lines below the heading
  # instead and missed tasks/show.html.erb, where the buttons sit seven lines
  # down — a spec that documented a convention it did not actually enforce.
  def actions_within_header(lines, header_line)
    base = indentation(lines[header_line])

    lines[(header_line + 1)..].each_with_index.take_while { |line, _|
      line.strip.empty? || indentation(line) > base
    }.map { |line, offset| [ line, header_line + offset + 1 ] }
  end

  def indentation(line) = line[/\A */].size

  def offenders
    Dir[Rails.root.join("app/views/**/*.erb")].sort.flat_map do |path|
      lines = File.readlines(path)

      lines.each_index.select { |i| lines[i].match?(STACKED_HEADER) }.flat_map do |i|
        actions_within_header(lines, i)
          .select { |line, _| line.match?(ACTION_GROUP) && !line.match?(WRAPS) }
          .map { |_, number| "#{path.sub("#{Rails.root}/", "")}:#{number + 1}" }
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

  # Guards the guard. Both misses above were the detector being too narrow, not
  # the convention being wrong, and a scanner that finds nothing looks identical
  # to a codebase that is clean.
  describe "the detector itself" do
    it "sees a group that sits well below the heading" do
      lines = <<~ERB.lines
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2>Title</h2>
            <p>One</p>
            <p>Two</p>
            <p>Three</p>
            <p>Four</p>
          </div>
          <div class="flex space-x-3">
          </div>
        </div>
      ERB

      offending = actions_within_header(lines, 0)
        .select { |line, _| line.match?(ACTION_GROUP) && !line.match?(WRAPS) }

      expect(offending.size).to eq(1)
    end

    it "sees a group with utilities between flex and space-x" do
      expect('<div class="flex items-center space-x-3">').to match(ACTION_GROUP)
    end

    it "stops at the end of the header container" do
      lines = <<~ERB.lines
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <h2>Title</h2>
        </div>
        <div class="flex space-x-3">
        </div>
      ERB

      expect(actions_within_header(lines, 0).map(&:first).join).not_to match(ACTION_GROUP)
    end

    it "passes a group that wraps" do
      expect('<div class="flex flex-wrap gap-3">').not_to match(ACTION_GROUP)
    end
  end
end
