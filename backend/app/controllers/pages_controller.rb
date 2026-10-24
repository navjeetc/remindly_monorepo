class PagesController < WebController
  # Public pages — no authentication required. The marketing layout and the
  # analytics-cookie cleanup both come from here.
  include PublicPage

  # The marketing homepage. Signed-in users go straight to their dashboard, so
  # daily use is unchanged and only logged-out visitors — and search engines —
  # see the marketing page.
  def home
    redirect_to dashboard_path if current_user
  end

  def how_to; end

  # The booking page for a free 15-minute call where we set Remindly up with a
  # family on the phone. A GoHighLevel calendar, so the link lives here once
  # rather than in every page that offers it, and bookings there are tagged
  # remindly-setup-call by a GHL workflow (the sub-account is shared; tags are
  # how Remindly's contacts are told apart).
  SETUP_CALL_URL = "https://api.leadconnectorhq.com/widget/booking/WCGg8BFRpRbgaoHbxlOd".freeze

  # Counted here and then sent on, so Admin -> Traffic shows how many people
  # pressed the offer: PublicPage counts only pages that render, and this one
  # redirects. Nothing about the visitor goes to GoHighLevel beyond the click
  # itself; whatever they type is typed on GHL's page.
  def setup_call
    count_setup_call_click
    redirect_to SETUP_CALL_URL, allow_other_host: true
  end

  # Legal pages, public to everyone (signed in or not).
  def privacy; end

  def terms; end

  # Answers the questions people type into a search engine before they know a
  # product like this exists ("how do I remind my mother to take her tablets").
  # Those searches never match a homepage; they match a page that asks the
  # question back.
  def faq; end

  # A printable daily routine sheet, useful to a family whether or not they ever
  # use Remindly. Public rather than gated behind the mailing list: it is a page
  # that can rank on its own ("printable medication schedule for elderly
  # parent"), and gating it would trade that away for addresses collected under
  # mild duress.
  def routine_sheet; end

  # A printable daily checklist for someone caring for a parent at home. Public
  # and ungated for the same reason the routine sheet is: it is useful on its
  # own, it can rank on its own, and a free printable is the kind of thing a
  # senior centre or a caregiver forum will link to — which is worth more than
  # the addresses gating it would collect.
  def caregiver_checklist; end

  # A landing page for one search: "reminder app for elderly parents", and the
  # phrasings around it. The homepage cannot serve that search well — it opens
  # on the feeling ("caring for a parent from a distance") because most of the
  # people who reach it arrived from a link someone sent them, already part
  # persuaded. Someone typing this phrase into a search engine has already
  # decided they want a piece of software and is asking which one, so this page
  # opens on the practical question instead and answers it in its own words
  # rather than the homepage's.
  #
  # Kept deliberately distinct from the homepage for that reason and one other:
  # two pages arguing the same thing in the same words are read as duplicates,
  # and a search engine picks one of them to show — usually not the one you
  # meant.
  def reminder_app_for_elderly_parents; end

  # Every public page that is not a blog post, in the order a person would meet
  # them. This is also the authoritative list of what is indexable: robots.txt
  # disallows everything else, so a page missing here is a page search engines
  # have no route to except an inbound link.
  STATIC_PATHS = %w[
    / /reminder-app-for-elderly-parents /how_to /faq /routine_sheet
    /caregiver_checklist /blog /privacy /terms
  ].freeze

  # Rendered rather than a static file so it cannot drift from the routes or
  # from the posts on disk. No layout — a sitemap is XML, and the marketing
  # layout would wrap it in HTML.
  def sitemap
    @paths = STATIC_PATHS + Post.all.map(&:path)

    render "sitemap", formats: :xml, layout: false
  end

  private

  # As count_this_page_view, and never worth failing the redirect over.
  def count_setup_call_click
    PageCount.record!(path: request.path, referrer: request.referer,
                      source: params[:from], user_agent: request.user_agent)
  rescue StandardError => e
    Rails.logger.warn("PageCount failed for #{request.path}: #{e.class}: #{e.message}")
  end
end
