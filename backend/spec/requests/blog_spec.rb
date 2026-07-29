require "rails_helper"

RSpec.describe "Blog", type: :request do
  def doc = Nokogiri::HTML(response.body)

  # The real posts on disk. If the blog is empty these specs prove nothing, so
  # they say so rather than passing quietly.
  let(:post) { Post.all.first }

  before { expect(Post.all).not_to be_empty, "no posts in content/posts" }

  describe "GET /blog" do
    it "lists published posts, newest first" do
      get "/blog"

      expect(response).to have_http_status(:ok)
      expect(doc.css(".post-list a").map { |a| a["href"] }).to include(post.path)
    end

    it "points the canonical URL at www.remindly.care" do
      get "/blog", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      expect(doc.at_css("link[rel='canonical']")&.[]("href")).to eq("https://www.remindly.care/blog")
    end
  end

  describe "GET /blog/:slug" do
    it "renders the post body as HTML" do
      get post.path

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to eq(post.title)
      expect(doc.at_css("article.post")).to be_present
    end

    it "carries the post's own title and description for search results" do
      get post.path

      expect(doc.at_css("title").text).to include(post.title)
      expect(doc.at_css("meta[name='description']")&.[]("content")).to eq(post.description)
    end

    # datePublished is what lets a result show a date, which is how a caregiver
    # judges whether advice is still current.
    it "publishes Article structured data with the publication date" do
      get post.path

      data = JSON.parse(doc.at_css("script[type='application/ld+json']").text)

      expect(data["@type"]).to eq("Article")
      expect(data["headline"]).to eq(post.title)
      expect(data["datePublished"]).to eq(post.published_on.iso8601)
    end

    # A renamed post leaves inbound links pointing at a slug that no longer
    # exists. That must 404 so it drops out of the index and we hear about it.
    it "404s for a slug that names no post" do
      get "/blog/not-a-real-post"

      expect(response).to have_http_status(:not_found)
    end

    # Same standard as the rest of the public pages: this is what gets indexed.
    it "loads no third-party assets" do
      get post.path

      refs = doc.css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact

      expect(refs.select { |u| u.start_with?("http", "//") }).to be_empty
    end

    it "issues no session cookie to an anonymous reader" do
      get post.path

      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end
  end

  # A free printable is the one asset on this site a senior centre or a
  # caregiver forum might actually link to, which is worth more to a new domain
  # than any amount of markup. So it stays public, ungated, and indexable.
  describe "GET /caregiver_checklist" do
    it "renders without authentication and without gating it behind the list" do
      get "/caregiver_checklist"

      expect(response).to have_http_status(:ok)
      expect(doc.css("ul.checklist li").count).to be >= 15
    end

    it "points the canonical URL at www.remindly.care" do
      get "/caregiver_checklist", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      expect(doc.at_css("link[rel='canonical']")&.[]("href"))
        .to eq("https://www.remindly.care/caregiver_checklist")
    end

    it "issues no session cookie" do
      get "/caregiver_checklist"

      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    # Both printables are useful to the same person, and each was otherwise
    # reachable only from the footer.
    it "links to the routine sheet, and the routine sheet links back" do
      get "/caregiver_checklist"
      expect(doc.css("a").map { |a| a["href"] }).to include("/routine_sheet")

      get "/routine_sheet"
      expect(doc.css("a").map { |a| a["href"] }).to include("/caregiver_checklist")
    end
  end

  describe "GET /routine_sheet" do
    it "renders without authentication and without gating it behind the list" do
      get "/routine_sheet"

      expect(response).to have_http_status(:ok)
      expect(doc.at_css(".sheet-table")).to be_present
    end

    it "issues no session cookie" do
      get "/routine_sheet"

      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end
  end
end
