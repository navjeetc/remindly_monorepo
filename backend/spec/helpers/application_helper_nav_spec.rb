require "rails_helper"

RSpec.describe ApplicationHelper do
  # Exercised through a bare includer rather than the Rails helper proxy: the
  # method only needs request.path, and this keeps the test about the matching
  # rule instead of view plumbing.
  let(:view) do
    Class.new do
      include ApplicationHelper
      attr_accessor :request
    end.new
  end

  def active_on?(current, link)
    view.request = Struct.new(:path).new(current)
    view.nav_link_class(link).include?("border-blue-500")
  end

  it "marks the exact page active" do
    expect(active_on?("/dashboard", "/dashboard")).to be(true)
  end

  # The pages someone is most likely to be on when they look up to see where
  # they are.
  it "marks a section active on its nested pages" do
    expect(active_on?("/dashboard/senior/5", "/dashboard")).to be(true)
    expect(active_on?("/admin/audit_logs/5", "/admin/audit_logs")).to be(true)
  end

  it "does not let one section claim another with a shared prefix" do
    expect(active_on?("/contacts_export", "/contact")).to be(false)
  end

  it "does not mark an unrelated page active" do
    expect(active_on?("/how_to", "/dashboard")).to be(false)
  end
end
