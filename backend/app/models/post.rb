# A blog post, read from a Markdown file rather than the database.
#
# Posts are written by us, deployed with the code, and reviewed in pull requests
# like anything else. That makes a database table the wrong home: it would need
# an admin UI, an editor, and a migration path, to hold content that changes
# less often than the code does. Files get version control and code review for
# free.
#
# Format is YAML front matter followed by Markdown:
#
#   ---
#   title: How to know whether your parent took their medication
#   description: One sentence for search results and the post list.
#   published_on: 2026-07-26
#   ---
#
#   Body in Markdown.
#
class Post
  include ActiveModel::Model

  ROOT = Rails.root.join("content", "posts")

  # Slug comes from the filename, so it cannot disagree with the file it names
  # and cannot be edited into something that collides with another post.
  attr_accessor :slug, :title, :description, :published_on, :body

  class NotFound < StandardError; end

  class << self
    # Newest first — the order a blog index is read in.
    #
    # Drafts are simply files with a published_on in the future, which keeps a
    # half-written post out of the index and out of the sitemap without a
    # separate flag to forget to flip.
    #
    # @return [Array<Post>]
    def all
      load_all.reject { |post| post.published_on.future? }.sort_by(&:published_on).reverse
    end

    # @param slug [String]
    # @return [Post]
    # @raise [NotFound] so the controller can turn it into a 404 rather than
    #   rendering a blank page for a URL that was never valid
    def find(slug)
      all.find { |post| post.slug == slug } || raise(NotFound, "no post: #{slug}")
    end

    def exists?(slug) = all.any? { |post| post.slug == slug }

    private

    # Parsed once per boot in production, and on every call in development so a
    # post being written shows up on reload without restarting the server.
    def load_all
      return parse_all if Rails.env.development?

      @load_all ||= parse_all
    end

    def parse_all
      Dir.glob(ROOT.join("*.md")).map { |path| parse(Pathname(path)) }
    end

    # Front matter is delimited by "---" lines. Anything that does not match the
    # expected shape raises here at load rather than rendering a post with a
    # blank title, which is the kind of thing that reaches production because it
    # still returns 200.
    def parse(path)
      raw = path.read
      match = raw.match(/\A---\s*\n(?<front>.*?)\n---\s*\n(?<body>.*)\z/m)
      raise "#{path.basename}: no YAML front matter" if match.nil?

      front = YAML.safe_load(match[:front], permitted_classes: [ Date ])

      %w[title description published_on].each do |key|
        raise "#{path.basename}: front matter is missing #{key}" if front[key].blank?
      end

      new(
        slug: path.basename(".md").to_s,
        title: front["title"],
        description: front["description"],
        published_on: front["published_on"].to_date,
        body: match[:body]
      )
    end
  end

  def path = "/blog/#{slug}"

  # html_safe is sound here specifically because posts are files in this repo,
  # written by us and reviewed in a pull request — never user input. Kramdown
  # passes raw HTML straight through, so if posts ever come from anywhere else,
  # this needs sanitizing before it is rendered.
  #
  # @return [ActiveSupport::SafeBuffer]
  def html = Kramdown::Document.new(body).to_html.html_safe
end
