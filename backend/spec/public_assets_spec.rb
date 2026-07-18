require "rails_helper"

# Everything under public/ is served to anyone who asks, with no auth and no
# robots.txt enforcement. Docs and manifests landed there once by being copied
# wholesale from clients/web — this keeps them from coming back.
RSpec.describe "public/ directory hygiene" do
  PUBLIC_ROOT = Rails.root.join("public")

  # Rails' own error pages are meant to be public.
  ALLOWED_HTML = %w[400.html 404.html 406-unsupported-browser.html 422.html 500.html].freeze

  it "serves no Markdown files" do
    markdown = Dir.glob(PUBLIC_ROOT.join("**", "*.md")).map { |p| relative(p) }

    expect(markdown).to be_empty,
      "Markdown under public/ is world-readable. Move it to the source directory " \
      "(clients/web/ or docs/) instead:\n  #{markdown.join("\n  ")}"
  end

  it "serves no package manifests or lockfiles" do
    manifests = Dir.glob(PUBLIC_ROOT.join("**", "{package.json,package-lock.json,yarn.lock,Gemfile,Gemfile.lock}"))
                   .map { |p| relative(p) }

    expect(manifests).to be_empty,
      "Dependency manifests under public/ disclose the stack and versions:\n  #{manifests.join("\n  ")}"
  end

  it "keeps the web client to its runtime files" do
    client_files = Dir.glob(PUBLIC_ROOT.join("client", "*")).map { |p| File.basename(p) }.sort

    expect(client_files).to eq(%w[app.js index.html styles.css])
  end

  def self.relative(path) = Pathname(path).relative_path_from(Rails.root).to_s
  def relative(path) = self.class.relative(path)
end
