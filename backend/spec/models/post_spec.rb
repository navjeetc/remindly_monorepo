require "rails_helper"

RSpec.describe Post do
  # Posts are files, so these write real files into a temporary directory and
  # point the model at it. Stubbing the parser instead would test nothing —
  # front matter handling is the entire behaviour of this class.
  # stub_const has to run inside the per-test lifecycle, so the directory is
  # created in before and cleaned up in after rather than wrapped in an around
  # block with Dir.mktmpdir.
  before do
    @dir = Pathname(Dir.mktmpdir)
    stub_const("Post::ROOT", @dir)
    Post.instance_variable_set(:@load_all, nil)
  end

  after { FileUtils.remove_entry(@dir) }

  def write_post(slug, front: {}, body: "Body text.")
    front = { "title" => "A title", "description" => "A description", "published_on" => "2026-01-01" }.merge(front)
    Post::ROOT.join("#{slug}.md").write("---\n#{front.to_yaml.sub(/\A---\n/, "")}---\n\n#{body}\n")
  end

  describe ".all" do
    it "reads title, description and date out of the front matter" do
      write_post("first", front: { "title" => "First post", "description" => "About things" })

      post = described_class.all.first

      expect(post.slug).to eq("first")
      expect(post.title).to eq("First post")
      expect(post.description).to eq("About things")
      expect(post.published_on).to eq(Date.new(2026, 1, 1))
    end

    it "returns newest first, the order a blog index is read in" do
      write_post("older", front: { "published_on" => "2026-01-01" })
      write_post("newer", front: { "published_on" => "2026-06-01" })

      expect(described_class.all.map(&:slug)).to eq(%w[newer older])
    end

    # A future date is the whole draft mechanism: no separate flag to forget to
    # flip, and a half-written post cannot leak into the index or the sitemap.
    it "hides posts dated in the future" do
      write_post("published", front: { "published_on" => Date.current.to_s })
      write_post("draft", front: { "published_on" => 1.year.from_now.to_date.to_s })

      expect(described_class.all.map(&:slug)).to eq(%w[published])
    end
  end

  describe ".find" do
    it "finds a post by the slug taken from its filename" do
      write_post("some-slug")
      expect(described_class.find("some-slug").slug).to eq("some-slug")
    end

    it "raises NotFound for a slug that names no post, so the controller can 404" do
      expect { described_class.find("nope") }.to raise_error(Post::NotFound)
    end

    it "will not serve a future-dated draft by guessing its URL" do
      write_post("draft", front: { "published_on" => 1.year.from_now.to_date.to_s })

      expect { described_class.find("draft") }.to raise_error(Post::NotFound)
    end
  end

  # These raise at load rather than rendering a post with a blank heading —
  # the kind of mistake that reaches production because the page still returns
  # 200 and nobody looks at it again.
  describe "malformed files" do
    it "refuses a file with no front matter" do
      Post::ROOT.join("bare.md").write("Just a body, no front matter.\n")

      expect { described_class.all }.to raise_error(/no YAML front matter/)
    end

    it "names the missing key when front matter is incomplete" do
      write_post("untitled", front: { "title" => "" })

      expect { described_class.all }.to raise_error(/missing title/)
    end
  end

  describe "#html" do
    it "renders the body as Markdown" do
      write_post("post", body: "Some **bold** text.")

      expect(described_class.find("post").html).to include("<strong>bold</strong>")
    end
  end

  describe "#path" do
    it "builds the blog URL from the slug" do
      write_post("a-post")
      expect(described_class.find("a-post").path).to eq("/blog/a-post")
    end
  end
end
