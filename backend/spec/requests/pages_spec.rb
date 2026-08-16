require "rails_helper"

RSpec.describe "Pages", type: :request do
  # Parse rather than string-match so the specs survive formatting and
  # attribute-order changes in the layout.
  def canonical_href
    Nokogiri::HTML(response.body).at_css("link[rel='canonical']")&.[]("href")
  end

  # Structured data is only worth anything if it parses. A trailing comma or an
  # escaping slip makes search engines drop the whole block silently, and nothing
  # about the rendered page looks wrong when that happens.
  def structured_data
    raw = Nokogiri::HTML(response.body).at_css("script[type='application/ld+json']")&.text
    raw && JSON.parse(raw)
  end

  # Ahoy skips anything it thinks is a bot, and a request spec sends no
  # User-Agent at all — so an analytics assertion made without one passes no
  # matter what the code does. Two specs here were green for exactly that
  # reason while /faq, /routine_sheet and the blog were recording a visit row
  # for every anonymous reader. Any spec about tracking has to send this.
  BROWSER = {
    "HTTP_USER_AGENT" =>
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  }.freeze

  describe "GET / (marketing homepage)" do
    def doc = Nokogiri::HTML(response.body)

    context "when logged out" do
      it "renders the marketing page instead of redirecting to login" do
        get "/"

        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("Caring for a parent")
      end

      # The site previously had no indexable homepage at all: / was
      # dashboard#index behind authenticate!, so it 302'd to /login.
      it "points the canonical URL at the root of www.remindly.care" do
        get "/", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
        expect(doc.at_css("link[rel='canonical']")&.[]("href")).to eq("https://www.remindly.care/")
      end

      it "carries a meta description for search results" do
        get "/"
        expect(doc.at_css("meta[name='description']")&.[]("content")).to be_present
      end

      # Early-user feedback, 2026-08: the page offered a nav "Sign in", a hero
      # "Get started" and a "See how it works" for what is really one decision,
      # and the primary did not say what you would be starting. One button
      # carries the action, and its label names the outcome.
      it "offers exactly one primary call to action, named by its outcome" do
        get "/"

        primaries = doc.css(".actions .btn-primary")
        expect(primaries.length).to eq(1), "the hero should offer one primary action, found #{primaries.length}"
        expect(primaries.first.text).to match(/set up reminders/i)
        expect(primaries.first["href"]).to eq("/login")
      end

      # The first objection is practical — what device, is there an app — and it
      # was answered five hundred words down, below an essay. It now sits above
      # the first screenshot, which is where someone deciding whether to bother
      # actually is.
      it "answers the device question before the first screenshot" do
        get "/"

        panel = doc.at_css("section.setup")
        expect(panel).to be_present, "the setup panel is gone"
        expect(panel.at_css("h2").text).to match(/already use/i)
        expect(panel.css("ol li").length).to eq(3)
        expect(panel.text).to match(/nothing to install/i)

        # Document order via XPath rather than Node#line: line numbers come from
        # libxml2 and are not dependable — 0 or nil under some parse options,
        # and unusable past 65535 lines — so a spec comparing them can fail on a
        # DOM that is in exactly the right order.
        first_shot = doc.at_css("figure.shot")
        expect(first_shot).to be_present
        expect(first_shot.xpath("preceding::section[contains(@class, 'setup')]")).not_to be_empty,
          "the setup panel should come before the first screenshot"
      end

      # The senior's screen is the answer to "my mother will never use this",
      # which is the objection that actually stops the buyer.
      it "shows the senior's screen before the caregiver's" do
        get "/"

        srcs = doc.css("figure.shot img").map { |img| img["src"] }
        expect(srcs.first).to eq("/screenshot-voice-reminders.webp")
        expect(doc.at_css("figure.shot figcaption").text).to match(/no app to learn/i)
      end

      # Remindly observes a button press. It cannot observe a swallowed tablet,
      # and medication is the wrong subject to be loose about — least of all in
      # the meta description, which is the sentence Google prints and therefore
      # the most-read claim on the site. The FAQ has always been careful here;
      # this page was not.
      it "never claims to know a dose was taken, including in the meta description" do
        get "/"

        description = doc.at_css("meta[name='description']")["content"]
        expect(description).to match(/marked done/i)

        # The FAQ deliberately asks "how do I know whether they actually took
        # it?" — the reader's question, answered precisely. Nothing on this page
        # has that excuse.
        # "a missed dose" is the same overclaim pointed the other way, and it is
        # the one that comes apart in practice — tablets taken, button not
        # pressed.
        expect(doc.at_css("body").text).not_to match(/\bdose is (taken|missed)\b|\bwhen they'?re taken\b/i)
      end

      # The FAQ carries the long-tail search content and the FAQPage graph, and
      # was reachable from here only through one link in the closing paragraph
      # and the footer — both below everything on the page.
      it "links to the questions page from where cost is discussed, not only at the foot" do
        get "/"

        # Walk only as far as the next heading. Taking every following sibling
        # would sweep up the closing paragraph's link and pass with or without
        # a link in this section, which is the thing being tested.
        heading = doc.at_css("h2:contains('What it costs')")
        expect(heading).to be_present, "the 'What it costs' section is gone"

        section = []
        node = heading.next_element
        while node && node.name != "h2"
          section << node
          node = node.next_element
        end

        hrefs = section.flat_map { |n| n.css("a").map { |a| a["href"] } }
        expect(hrefs).to include("/faq"), "nothing links to the FAQ from the section about cost"
      end

      # /how_to is otherwise an orphan - nothing links to it, so nothing finds it.
      it "links to the guide and to sign in" do
        get "/"

        hrefs = doc.css("a").map { |a| a["href"] }
        expect(hrefs).to include("/how_to")
        expect(hrefs).to include("/login")
      end

      it "offers a way to make contact" do
        get "/"
        expect(doc.css("a").map { |a| a["href"] }).to include("mailto:hello@remindly.care")
      end

      # Onboarding is self-serve now: first sign-in asks which role you are and
      # takes you straight in, so the homepage sets that expectation.
      it "explains the self-serve first-sign-in flow" do
        get "/"
        expect(response.body).to include("asks one question")
      end

      # Excluding the path in Ahoy::Store stops the visit row, but Ahoy still
      # sets its cookies — so an anonymous reader went away carrying a
      # month-long identifier anyway. Half a privacy fix.
      it "leaves no analytics cookie on an anonymous visitor" do
        get "/"

        %w[ahoy_visit ahoy_visitor].each do |name|
          expect(response.cookies[name]).to be_blank, "#{name} was left set"
        end
      end

      # Adding csrf_meta_tags here would touch the session and start issuing a
      # session cookie to every anonymous reader of a public page.
      it "issues no session cookie" do
        get "/"
        expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
      end

      # The dashboard layout loads Tailwind from a CDN. This page is the one
      # search engines index, so it must not block on a third-party request.
      it "loads no third-party assets" do
        get "/"

        # img is in the list because the screenshots could just as easily have
        # been hotlinked from an image host, which would put a third-party
        # request back on the one page that must not make any.
        external = doc.css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
          .map { |n| n["src"] || n["href"] }.compact

        # "//cdn.example.com/x.js" fetches over the page's own scheme, so a check
        # for "http" alone would pass while the browser still made the request.
        expect(external.select { |u| u.start_with?("http", "//") }).to be_empty
      end

      # Most people meet this site through a link someone shared. Without an
      # image, every one of those links renders as a bare grey box.
      it "carries a social preview image at an absolute URL on the canonical host" do
        get "/", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

        expect(doc.at_css("meta[property='og:image']")&.[]("content"))
          .to eq("https://www.remindly.care/og-image.png")
        expect(doc.at_css("meta[name='twitter:card']")&.[]("content")).to eq("summary_large_image")
      end

      it "ships the file that og:image points at" do
        expect(Rails.root.join("public", "og-image.png")).to exist
      end

      # The price is the reason for the structured data: it is what lets a search
      # result say "free", which is the fact most likely to earn the click.
      it "declares itself as free software in its structured data" do
        get "/"

        expect(structured_data["@type"]).to eq("SoftwareApplication")
        expect(structured_data.dig("offers", "price")).to eq("0")
      end

      it "says plainly that it costs nothing" do
        get "/"
        expect(response.body).to match(/free to use/i)
      end

      describe "the product screenshots" do
        before { get "/" }

        def screenshots = doc.css("figure.shot img")

        it "shows both sides of the product — what the senior sees and what the caregiver sees" do
          sources = screenshots.map { |img| img["src"] }

          expect(sources).to include("/screenshot-voice-reminders.webp")
          expect(sources).to include("/screenshot-tasks.webp")
        end

        it "ships the files the page points at" do
          screenshots.each do |img|
            path = Rails.public_path.join(img["src"].delete_prefix("/"))
            expect(path).to exist, "#{img["src"]} is referenced but not in public/"
          end
        end

        # Half the point of this product is that it is usable by people who
        # cannot read a screen well. A marketing page for them that ships
        # undescribed images would be an odd advertisement for the claim.
        it "describes every image for anyone who cannot see it" do
          screenshots.each do |img|
            expect(img["alt"].to_s.length).to be > 40,
              "#{img["src"]} needs alt text that actually describes the screenshot"
          end
        end

        # Without intrinsic dimensions the browser cannot reserve the space, and
        # the text below jumps as each image arrives.
        it "declares intrinsic dimensions so nothing jumps as they load" do
          screenshots.each do |img|
            expect(img["width"]).to be_present, "#{img["src"]} has no width"
            expect(img["height"]).to be_present, "#{img["src"]} has no height"
          end
        end

        # They sit well below the fold, and this page is the one that has to
        # stay fast. The first screenshot moved up the document in 2026-08,
        # which briefly looked like a reason to load it eagerly — but the hero,
        # the buttons, the free note and the setup panel still run past the
        # first screen, so it is not visible on arrival on any common viewport
        # and eager loading only competes with the content that is.
        it "defers them until they are scrolled to" do
          expect(screenshots.map { |img| img["loading"] }).to all(eq("lazy"))
        end
      end
    end

    context "when signed in" do
      it "redirects to the dashboard so daily use is unchanged" do
        user = User.create!(email: "caregiver@example.com", tz: "America/New_York", name: "Cara")
        post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

        get "/"
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  # The marketing footer is the one place these legal pages are linked from, so
  # nothing finds them if the links are missing.
  describe "footer links from the homepage" do
    it "links to the privacy policy and terms" do
      get "/"
      hrefs = Nokogiri::HTML(response.body).css("footer a").map { |a| a["href"] }
      expect(hrefs).to include("/privacy").and include("/terms")
    end
  end

  describe "GET /privacy" do
    it "renders the privacy policy without authentication" do
      get "/privacy"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1").text).to include("Privacy")
    end

    it "points the canonical URL at www.remindly.care even from the legacy subdomain" do
      get "/privacy", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
      expect(canonical_href).to eq("https://www.remindly.care/privacy")
    end

    it "states the deletion-on-request commitment" do
      get "/privacy"
      expect(response.body).to match(/delete/i)
    end

    # The policy says analytics aren't collected on public pages, so this page must
    # not persist an Ahoy visit for an anonymous reader.
    it "records no analytics visit for an anonymous visitor" do
      expect { get "/privacy", headers: BROWSER }.not_to change { Ahoy::Visit.count }
    end

    # It is the indexable set of pages, so it must not block on a third-party asset.
    it "loads no third-party assets" do
      get "/privacy"
      external = Nokogiri::HTML(response.body).css("script[src], link[rel='stylesheet']").map { |n| n["src"] || n["href"] }.compact
      expect(external.select { |u| u.start_with?("http", "//") }).to be_empty
    end
  end

  describe "GET /terms" do
    it "renders the terms without authentication" do
      get "/terms"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1").text).to include("Terms")
    end

    it "points the canonical URL at www.remindly.care" do
      get "/terms"
      expect(canonical_href).to eq("https://www.remindly.care/terms")
    end

    # The honest centerpiece — Remindly is not a medical device — must be present.
    it "carries the medical disclaimer" do
      get "/terms"
      expect(response.body).to match(/not a medical device/i)
    end

    it "links to the privacy policy" do
      get "/terms"
      expect(Nokogiri::HTML(response.body).css("a").map { |a| a["href"] }).to include("/privacy")
    end

    it "records no analytics visit for an anonymous visitor" do
      expect { get "/terms", headers: BROWSER }.not_to change { Ahoy::Visit.count }
    end
  end

  # Someone landing on a blog post from a search had no visible route anywhere
  # except Sign in — the one thing they are not ready to do.
  describe "the top navigation" do
    def nav_links(path)
      get path
      Nokogiri::HTML(response.body).css("header nav.top-nav a")
    end

    it "offers the evaluating path on every public page" do
      (PagesController::STATIC_PATHS + [ Post.all.first.path ]).each do |path|
        hrefs = nav_links(path).map { |a| a["href"] }

        expect(hrefs).to include("/how_to", "/faq", "/blog"), "#{path} nav has #{hrefs.inspect}"
      end
    end

    # Deliberately three destinations plus one action, not the footer's seven.
    # The rest belong where people go looking for them.
    it "stays short, and keeps the legal pages in the footer" do
      hrefs = nav_links("/").map { |a| a["href"] }

      expect(hrefs.size).to eq(4)
      expect(hrefs).not_to include("/privacy")
      expect(hrefs).not_to include("/terms")
    end

    it "sends a signed-out visitor to sign in, and a signed-in one to their dashboard" do
      expect(nav_links("/faq").map { |a| a["href"] }).to include("/login")

      user = User.create!(email: "nav@example.com", role: :caregiver, tz: "America/New_York", name: "Nav")
      post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

      hrefs = nav_links("/faq").map { |a| a["href"] }
      expect(hrefs).to include("/dashboard")
      expect(hrefs).not_to include("/login")
    end

    # These pages ship no JavaScript, and three links do not justify starting.
    it "needs no JavaScript to work" do
      get "/"

      expect(Nokogiri::HTML(response.body).css("header script")).to be_empty
    end

    # /how_to was "How it works" at the top and "How Remindly works" in the
    # footer — the same page under two names, which makes a reader wonder
    # whether they are two pages.
    it "gives each destination one label, wherever it appears" do
      get "/"
      doc = Nokogiri::HTML(response.body)

      labels = Hash.new { |h, k| h[k] = Set.new }
      doc.css("header nav.top-nav a, footer a").each do |link|
        labels[link["href"]] << link.text.strip
      end

      inconsistent = labels.select { |_href, names| names.size > 1 }
      expect(inconsistent).to be_empty, "same destination, different labels: #{inconsistent.inspect}"
    end

    # Both of these were chosen for tone and cost legibility. People scan for
    # the word they expect: "Writing" for a blog, and "Questions" for what every
    # other site on the internet calls an FAQ — which the page's own title
    # already called it.
    it "uses the conventional label for the blog and the FAQ, in both navigations" do
      get "/"
      doc = Nokogiri::HTML(response.body)

      top = doc.css("header nav.top-nav a").map(&:text).map(&:strip)
      foot = doc.css("footer a").map(&:text).map(&:strip)

      expect(top).to include("Blog", "FAQ")
      expect(foot).to include("Blog", "FAQ")
      expect(top + foot).not_to include("Writing")
      expect(top + foot).not_to include("Questions")
    end
  end

  # Page-level graphs say what a given page is. Nothing said who publishes the
  # site, which is the association search engines use to tie a domain, a name and
  # a support address together.
  describe "site-wide publisher structured data" do
    def graphs(path)
      get path
      Nokogiri::HTML(response.body)
        .css("script[type='application/ld+json']")
        .map { |node| JSON.parse(node.text) }
    end

    it "declares the organisation and the site on every public page" do
      (PagesController::STATIC_PATHS + [ Post.all.first.path ]).each do |path|
        types = graphs(path).flat_map { |g| g["@graph"]&.map { |n| n["@type"] } || [ g["@type"] ] }

        expect(types).to include("Organization"), "#{path} declares #{types.inspect}"
        expect(types).to include("WebSite"), "#{path} declares #{types.inspect}"
      end
    end

    # A page that declares something of its own must keep doing so — the
    # publisher graph is additional, not a replacement.
    it "leaves the page's own graph in place" do
      expect(graphs("/faq").map { |g| g["@type"] }).to include("FAQPage")
      expect(graphs("/").map { |g| g["@type"] }).to include("SoftwareApplication")
      expect(graphs(Post.all.first.path).map { |g| g["@type"] }).to include("Article")
    end

    # Every block has to parse. An unparseable one is dropped silently and
    # nothing about the page looks wrong.
    #
    # Deliberately not asserting how many there are: the count is not the
    # behaviour, and pinning it would fail the day a legitimate BreadcrumbList
    # is added.
    it "emits only valid JSON" do
      expect { graphs("/") }.not_to raise_error
      expect(graphs("/")).to all(be_a(Hash))
      expect(graphs("/")).not_to be_empty
    end
  end

  # Costing nothing is the fact most likely to decide whether a caregiver
  # comparing options clicks through, and for a while only the homepage carried
  # it. The homepage is also the least likely landing page for the long-tail
  # searches this site is written for.
  describe "saying that it is free" do
    def doc = Nokogiri::HTML(response.body)

    # The <title> is the blue link text in a search result, so a page that
    # ranks without it in the title never gets to make the point at all.
    it "carries it in the title of every page written to be landed on" do
      %w[/ /reminder-app-for-elderly-parents /faq /how_to /routine_sheet].each do |path|
        get path

        expect(doc.at_css("title").text).to match(/free/i), "#{path} title does not mention it"
      end
    end

    # Someone arriving on the FAQ or a blog post from a search could otherwise
    # read several pages without ever learning it.
    it "shows the badge on every public page, including the blog" do
      [ "/", "/faq", "/how_to", "/routine_sheet", "/blog", Post.all.first.path ].each do |path|
        get path

        expect(doc.at_css("header .badge-free")&.text).to eq("Free"), "no badge on #{path}"
      end
    end

    # The question a wary reader actually has. Answering it is worth more than
    # repeating the word, and it is itself a thing people search for.
    it "answers what the catch is, as a question search engines can surface" do
      get "/faq"

      questions = structured_data["mainEntity"].map { |q| q["name"] }
      expect(questions).to include(a_string_matching(/why is remindly free/i))

      answer = structured_data["mainEntity"].find { |q| q["name"].match?(/why is remindly free/i) }
      expect(answer.dig("acceptedAnswer", "text")).to match(/no catch/i)
    end
  end

  # The privacy policy tells anonymous readers that public pages are not
  # tracked. Ahoy's exclusion list was four hardcoded paths, so every public
  # page added after it was written recorded an IP, referrer and device for
  # every stranger who read it — with nothing failing to say so.
  describe "analytics on public pages" do
    def public_paths = PagesController::STATIC_PATHS + Post.all.map(&:path)

    it "records no visit on any public page" do
      public_paths.each do |path|
        expect { get path, headers: BROWSER }.not_to(change { Ahoy::Visit.count }, "#{path} recorded a visit")
      end
    end

    # Not a page anyone reads — it exists to be fetched by a machine, so it is
    # not in STATIC_PATHS and was tracked until it was named explicitly.
    it "records no visit for the sitemap" do
      expect { get "/sitemap.xml", headers: BROWSER }.not_to change { Ahoy::Visit.count }
    end

    it "records no visit when someone joins the mailing list" do
      expect {
        post "/subscribers", params: { email: "quiet@example.com" }, headers: BROWSER
      }.not_to change { Ahoy::Visit.count }
    end

    # The counterpart: signed-in activity is still tracked, which is where the
    # useful signal is and where people do have an account with us. Without
    # this, "exclude everything" would pass the specs above.
    it "still records visits for signed-in activity" do
      user = User.create!(email: "tracked@example.com", role: :caregiver, tz: "America/New_York", name: "Tracked")

      expect {
        post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) },
          headers: BROWSER
      }.to change { Ahoy::Visit.count }.by(1)
    end
  end

  describe "GET /how_to" do
    it "renders the guide without authentication" do
      get "/how_to"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1")&.text.to_s).to include("How to use Remindly")
    end

    # The point of serving this on the marketing layout: no CDN Tailwind, and no
    # session cookie for an anonymous, indexable page.
    it "loads no third-party assets" do
      get "/how_to"
      refs = Nokogiri::HTML(response.body).css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact
      expect(refs.select { |u| u.start_with?("http", "//") }).to be_empty
    end

    it "issues no session cookie to an anonymous visitor" do
      get "/how_to"
      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    # A signed-in user reaching the guide from their dashboard must not see the
    # marketing "Sign in" nav — they get a way back to their dashboard instead.
    it "shows a signed-in user a dashboard link, not a sign-in prompt" do
      user = User.create!(email: "cara@example.com", role: :caregiver, tz: "America/New_York", name: "Cara")
      post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

      get "/how_to"
      nav_hrefs = Nokogiri::HTML(response.body).css("header a, footer a").map { |a| a["href"] }
      expect(nav_hrefs).to include(dashboard_path)
      expect(nav_hrefs).not_to include(login_path)
    end

    it "points the canonical URL at www.remindly.care" do
      get "/how_to"
      expect(canonical_href).to eq("https://www.remindly.care/how_to")
    end

    it "keeps the canonical URL on www.remindly.care when served from the legacy subdomain" do
      get "/how_to", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
      expect(canonical_href).to eq("https://www.remindly.care/how_to")
    end

    it "ignores query strings so tracking params don't split the canonical" do
      get "/how_to", params: { utm_source: "newsletter" }
      expect(canonical_href).to eq("https://www.remindly.care/how_to")
    end
  end

  describe "GET /faq" do
    it "renders without authentication" do
      get "/faq"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1").text).to include("Questions")
    end

    it "points the canonical URL at www.remindly.care" do
      get "/faq"
      expect(canonical_href).to eq("https://www.remindly.care/faq")
    end

    # The whole point of the page: rich results for the questions caregivers
    # actually type. Google drops a FAQPage whose questions are not also visible
    # on the page, so both come from one source in the template.
    it "publishes every visible question as FAQPage structured data" do
      get "/faq"

      expect(structured_data["@type"]).to eq("FAQPage")

      asked = structured_data["mainEntity"].map { |q| q["name"] }
      shown = Nokogiri::HTML(response.body).css("h2").map(&:text)

      expect(asked).to all(be_in(shown))
      expect(structured_data["mainEntity"]).to all(include("acceptedAnswer"))
    end

    # Trust is the thing being sold here, and the honest answers are the ones a
    # worried family most needs before handing over their parent's medication
    # schedule. They are also the two most tempting lines to quietly drop.
    it "keeps the answers that are 'no'" do
      get "/faq"

      expect(response.body).to match(/medical device/i)
      expect(response.body).to match(/not a substitute/i)
      expect(response.body).to match(/page have to stay open/i)
    end

    it "issues no session cookie to an anonymous visitor" do
      get "/faq"
      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    it "loads no third-party assets" do
      get "/faq"
      refs = Nokogiri::HTML(response.body).css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact
      expect(refs.select { |u| u.start_with?("http", "//") }).to be_empty
    end
  end

  # A landing page for one search — "reminder app for elderly parents" — rather
  # than a second homepage. The specs that matter here are the ones that keep it
  # from becoming the latter: a distinct title, questions that are not the FAQ's,
  # and a route in from the homepage so it is not reachable only by sitemap.
  describe "GET /reminder-app-for-elderly-parents" do
    landing = "/reminder-app-for-elderly-parents"

    def doc = Nokogiri::HTML(response.body)

    it "renders without authentication" do
      get landing

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to match(/reminder app for elderly parents/i)
    end

    # The phrase has to be in the words a search engine actually prints — the
    # blue link and the grey sentence under it — or the page is written for a
    # search it never enters.
    it "carries the search phrase in the title and the meta description" do
      get landing

      expect(doc.at_css("title").text).to match(/reminder app for elderly parents/i)
      expect(doc.at_css("meta[name='description']")["content"])
        .to match(/reminder app for elderly parents/i)
    end

    it "points the canonical URL at www.remindly.care, including from the legacy subdomain" do
      get landing, headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      expect(canonical_href).to eq("https://www.remindly.care#{landing}")
    end

    # Same standard as the homepage. This page argues harder for the product,
    # which is exactly when the claim is most tempting to round up — Remindly
    # observes a button press, not a swallowed tablet.
    it "never claims to know a dose was taken, including in the meta description" do
      get landing

      expect(doc.at_css("meta[name='description']")["content"]).to match(/marked done/i)
      expect(doc.at_css("body").text).not_to match(/\bdose is (taken|missed)\b|\bwhen they'?re taken\b/i)
      expect(response.body).to match(/not a substitute/i)
    end

    it "opens with one primary call to action, pointing at sign-in" do
      get landing

      hero = doc.at_css(".actions")
      primaries = hero.css(".btn-primary")

      expect(primaries.length).to eq(1)
      expect(primaries.first["href"]).to eq("/login")
    end

    it "publishes every visible question as FAQPage structured data" do
      get landing

      expect(structured_data["@type"]).to eq("FAQPage")

      asked = structured_data["mainEntity"].map { |q| q["name"] }
      shown = doc.css("h3").map(&:text)

      expect(asked).not_to be_empty
      expect(asked).to all(be_in(shown))
      expect(structured_data["mainEntity"]).to all(include("acceptedAnswer"))
    end

    # The failure this page invites: two of our own pages answering the same
    # question in the same words, which a search engine reads as one page
    # duplicated and shows whichever it prefers — usually not the one intended.
    it "asks different questions than the FAQ does" do
      get landing
      here = structured_data["mainEntity"].map { |q| q["name"] }

      get "/faq"
      there = structured_data["mainEntity"].map { |q| q["name"] }

      expect(here & there).to be_empty, "same question on both pages: #{(here & there).inspect}"
    end

    # A page nothing links to is a page a search engine has little reason to
    # think matters, however diligently the sitemap lists it.
    it "is linked from the homepage" do
      get "/"

      expect(doc.css("a").map { |a| a["href"] }).to include(landing)
    end

    it "is listed in the sitemap" do
      get "/sitemap.xml"

      locs = Nokogiri::XML(response.body).css("url loc").map(&:text)
      expect(locs).to include("https://www.remindly.care#{landing}")
    end

    it "ships the screenshot it points at, described for anyone who cannot see it" do
      get landing

      doc.css("figure.shot img").each do |img|
        expect(Rails.public_path.join(img["src"].delete_prefix("/"))).to exist
        expect(img["alt"].to_s.length).to be > 40
        expect(img["width"]).to be_present
        expect(img["height"]).to be_present
      end
    end

    it "issues no session cookie to an anonymous visitor" do
      get landing

      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    it "loads no third-party assets" do
      get landing

      refs = doc.css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact
      expect(refs.select { |u| u.start_with?("http", "//") }).to be_empty
    end
  end

  describe "GET /sitemap.xml" do
    it "serves XML at the path robots.txt advertises" do
      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
    end

    # A sitemap on one hostname pointing at pages that claim another as canonical
    # is a conflicting signal, and this app answers on three hostnames.
    it "lists every public page as an absolute URL on the canonical host" do
      get "/sitemap.xml", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      locs = Nokogiri::XML(response.body).css("url loc").map(&:text)
      expected = PagesController::STATIC_PATHS + Post.all.map(&:path)

      expect(locs).to match_array(expected.map { |path| "https://www.remindly.care#{path}" })
    end

    # A post is only worth writing if it can be found, and a new file on disk is
    # the whole of "publishing" here — nothing else has to be remembered.
    it "picks up blog posts from disk without anything else being edited" do
      get "/sitemap.xml"

      locs = Nokogiri::XML(response.body).css("url loc").map(&:text)

      expect(Post.all).not_to be_empty, "no posts on disk, so this proves nothing"
      expect(locs).to include("https://www.remindly.care#{Post.all.first.path}")
    end

    # Listing a page that robots.txt forbids tells a crawler to fetch something
    # it is also told not to, and Search Console reports it as an error.
    it "lists nothing that robots.txt disallows" do
      get "/sitemap.xml"

      disallowed = Rails.root.join("public", "robots.txt").read
        .scan(/^Disallow:\s*(\S+)/).flatten

      listed = Nokogiri::XML(response.body).css("url loc")
        .map { |n| URI.parse(n.text).path }

      # robots.txt matches by prefix, so a rule blocks a path when the rule is a
      # prefix of it — not the other way round. Comparing the other direction
      # passes "/" against every rule and fails on all of them.
      listed.each do |path|
        blocking = disallowed.select { |rule| path.start_with?(rule) }

        expect(blocking).to be_empty,
          "#{path} is in the sitemap but blocked by robots.txt rule(s): #{blocking.join(", ")}"
      end
    end

    it "is advertised in robots.txt" do
      robots = Rails.root.join("public", "robots.txt").read
      expect(robots).to include("Sitemap: https://www.remindly.care/sitemap.xml")
    end
  end
end
