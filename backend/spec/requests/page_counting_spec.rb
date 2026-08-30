# frozen_string_literal: true

require "rails_helper"

# The counter added to PublicPage. The model spec covers what is stored; this
# covers the thing that would actually be a regression — that measuring these
# pages did not cost the property they were built to have.
RSpec.describe "Public page counting", type: :request do
  # A method rather than a constant — constants in a describe block land on
  # Object and collide across spec files.
  def browser_ua
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end

  def browse(path, headers: {})
    get path, headers: { "HTTP_USER_AGENT" => browser_ua }.merge(headers)
  end

  it "counts a view of a public page" do
    expect { browse("/faq") }.to change { PageCount.humans.sum(:count) }.by(1)
    expect(PageCount.sole.path).to eq("/faq")
  end

  # The reason the counter exists, end to end: a link shared somewhere, followed
  # by a person, showing up as that somewhere.
  it "records which site the visitor came from" do
    browse("/", headers: { "HTTP_REFERER" => "https://www.reddit.com/r/AgingParents/comments/xyz/" })

    expect(PageCount.referred.pluck(:referrer_host)).to eq([ "reddit.com" ])
  end

  # Apps and forums routinely strip the referrer, which is why a tag we put on
  # the link ourselves is worth having as well.
  it "records a campaign tag from the link" do
    browse("/?from=agingparents")

    expect(PageCount.tagged.pluck(:source)).to eq([ "agingparents" ])
  end

  # The whole privacy position of these pages, restated as a test. Ahoy's
  # cookies are dropped and the marketing layout omits csrf_meta_tags so no
  # session cookie is issued either; a counter that reintroduced either would
  # defeat the point of counting this way.
  #
  # Asserted on the net effect rather than the raw Set-Cookie header, which
  # legitimately carries both a set and an immediate expiry: Ahoy sets its
  # cookie while the request runs and the concern deletes it afterwards, so the
  # browser is told to create the cookie and then to drop it. What matters is
  # what the visitor is left holding, which is nothing.
  it "still sets no cookie on an anonymous visitor" do
    browse("/faq")

    expect(response.cookies.compact).to be_empty
    %w[ahoy_visit ahoy_visitor _remindly_session].each do |name|
      expect(response.cookies[name]).to be_blank, "#{name} was left set"
    end
  end

  it "writes no Ahoy visit for a public page" do
    expect { browse("/faq") }.not_to change(Ahoy::Visit, :count)
  end

  # /sitemap.xml runs through the same controller and concern. Counting it would
  # mix crawler plumbing into the number meant to describe readers.
  it "counts only HTML GETs" do
    browse("/sitemap.xml")
    expect(PageCount.count).to eq(0)
  end

  # The regression this file did not have, and the deploy that followed found.
  #
  # curl, a good many crawlers and anything that is not a browser send
  # `Accept: */*`, which Rails resolves to Mime::ALL — so `request.format.html?`
  # was false while the HTML template rendered and returned 200 text/html, and
  # nothing was counted. Rails' own test `get` resolves to html, which is
  # exactly why the original spec passed and production did not.
  it "counts a request that asks for */* and is served HTML" do
    expect {
      browse("/faq", headers: { "HTTP_ACCEPT" => "*/*" })
    }.to change { PageCount.humans.sum(:count) }.by(1)
  end

  it "still refuses the sitemap when it is requested as */*" do
    browse("/sitemap.xml", headers: { "HTTP_ACCEPT" => "*/*" })
    expect(PageCount.count).to eq(0)
  end

  # A tally is never worth a 500 on the pages strangers and search engines see.
  it "serves the page even if counting fails" do
    allow(PageCount).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, "boom")

    browse("/faq")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Remindly")
  end
end
