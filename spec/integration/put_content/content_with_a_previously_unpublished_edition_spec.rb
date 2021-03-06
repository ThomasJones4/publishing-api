require "rails_helper"

RSpec.describe "PUT /v2/content when creating a draft for a previously unpublished edition" do
  include_context "PutContent call"
  before do
    Timecop.freeze("2017-01-02 12:23")
  end

  after do
    Timecop.return
  end

  let(:temporary_first_published_at) { "2016-01-02 12:23" }

  before do
    Timecop.freeze(Time.local(2017, 9, 1, 12, 0, 0))
    create(:unpublished_edition,
      document: create(:document, content_id: content_id, stale_lock_version: 2),
      user_facing_version: 5,
      base_path: base_path,
      temporary_first_published_at: temporary_first_published_at,
    )
  end

  it "creates the draft's lock version using the unpublished lock version as a starting point" do
    put "/v2/content/#{content_id}", params: payload.to_json

    edition = Edition.last

    expect(edition).to be_present
    expect(edition.document.content_id).to eq(content_id)
    expect(edition.state).to eq("draft")
    expect(edition.document.stale_lock_version).to eq(3)
  end

  it "creates the draft's user-facing version using the unpublished user-facing version as a starting point" do
    put "/v2/content/#{content_id}", params: payload.to_json

    edition = Edition.last

    expect(edition).to be_present
    expect(edition.document.content_id).to eq(content_id)
    expect(edition.state).to eq("draft")
    expect(edition.user_facing_version).to eq(6)
  end

  it "sets temporary_first_published_at to the previously unpublished verson's value" do
    put "/v2/content/#{content_id}", params: payload.to_json

    edition = Edition.last

    expect(edition.temporary_first_published_at)
      .to eq(temporary_first_published_at)
  end
end
