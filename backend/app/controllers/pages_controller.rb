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
end
