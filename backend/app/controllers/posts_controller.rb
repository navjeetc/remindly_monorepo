# The blog. Posts are Markdown files in content/posts — see Post.
class PostsController < WebController
  include PublicPage

  # A slug that names no post is a URL that was never valid, usually a typo or a
  # link to a post that was renamed. 404 rather than an empty page, so it is not
  # indexed and so we hear about broken inbound links.
  rescue_from Post::NotFound, with: :not_found

  def index
    @posts = Post.all
  end

  def show
    @post = Post.find(params[:slug])
  end

  private

  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
