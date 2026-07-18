require "rails_helper"

# The voice web client exists twice: clients/web/ is where it's developed and
# what `npm run dev` runs, backend/public/client/ is what Rails actually serves.
# They are kept in sync by hand, and drifted for ~6 weeks once — production
# missed the iPad voice-unlock improvements the whole time, which nobody noticed
# because both copies "worked".
#
# clients/web/ is authoritative. Run `make sync-web-client` to update the served
# copy. A Dockerfile copy step can't do this: deploy.sh builds with backend/ as
# the context, so ../clients/web is unreachable from the image build.
RSpec.describe "voice web client sync" do
  SOURCE_DIR = Rails.root.join("..", "clients", "web")
  SERVED_DIR = Rails.root.join("public", "client")
  RUNTIME_FILES = %w[app.js index.html styles.css].freeze

  # Skip only when the whole client isn't checked out (a backend-only checkout).
  # Once the directory is present, a missing runtime file is a real failure —
  # keying the skip off the individual file would let a deletion or rename pass
  # silently, which is the same blind spot this spec exists to close.
  before do
    skip "clients/web is not checked out" unless SOURCE_DIR.directory?
  end

  RUNTIME_FILES.each do |filename|
    it "serves the same #{filename} that clients/web develops" do
      source = SOURCE_DIR.join(filename)
      served = SERVED_DIR.join(filename)

      expect(source).to exist,
        "clients/web/#{filename} is missing. If it was deleted or renamed, " \
        "update RUNTIME_FILES and the WEB_CLIENT_FILES list in the Makefile."
      expect(served).to exist

      expect(served.read).to eq(source.read),
        "backend/public/client/#{filename} has drifted from clients/web/#{filename}. " \
        "Production serves the copy under public/, so this drift ships. " \
        "Run `make sync-web-client` from the repo root."
    end
  end
end
