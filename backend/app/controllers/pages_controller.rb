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

  # Every public page that is not a blog post, in the order a person would meet
  # them. This is also the authoritative list of what is indexable: robots.txt
  # disallows everything else, so a page missing here is a page search engines
  # have no route to except an inbound link.
  STATIC_PATHS = %w[/ /how_to /faq /routine_sheet /caregiver_checklist /blog /privacy /terms].freeze

  # Rendered rather than a static file so it cannot drift from the routes or
  # from the posts on disk. No layout — a sitemap is XML, and the marketing
  # layout would wrap it in HTML.
  def sitemap
    @paths = STATIC_PATHS + Post.all.map(&:path)

    render "sitemap", formats: :xml, layout: false
  end
end
