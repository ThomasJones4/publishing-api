require "rails_helper"

RSpec.describe "Message bus", type: :request do
  context "/content" do
    let(:request_path) { "/content#{base_path}" }

    it "places a JSON message on the queue" do
      expect(DownstreamService).to receive(:broadcast_to_message_queue).with(anything, 'links')
      expect(DownstreamService).to receive(:broadcast_to_message_queue).with(anything, 'major')
      put request_path, params: content_item_params.to_json
    end

    context "minor update type" do
      it "uses the update type for the routing key on publish and 'links' for the link update" do
        expect(DownstreamService).to receive(:broadcast_to_message_queue).with(anything, 'links')
        expect(DownstreamService).to receive(:broadcast_to_message_queue).with(anything, 'minor')
        put request_path, params: content_item_params.merge(update_type: "minor").to_json
      end
    end

    it "publishes a message for a redirect update" do
      expect(DownstreamService).to_not receive(:broadcast_to_message_queue)
      put request_path, params: redirect_content_item.to_json
    end
  end

  context "/draft-content" do
    it "doesn't send any messages" do
      expect(DownstreamService).to_not receive(:broadcast_to_message_queue)
      expect(PublishingAPI.service(:queue_publisher)).not_to receive(:send_message)

      put "/draft-content#{base_path}", params: content_item_params.to_json

      expect(response.status).to eq(200)
    end
  end

  context "/v2/content" do
    it "doesn't send any messages" do
      expect(DownstreamService).to_not receive(:broadcast_to_message_queue)
      expect(PublishingAPI.service(:queue_publisher)).not_to receive(:send_message)

      put "/v2/content/#{content_id}", params: v2_content_item.to_json

      expect(response.status).to eq(200)
    end
  end

  context "/v2/links" do
    let(:request_body) { patch_links_attributes.to_json }
    let(:request_path) { "/v2/links/#{content_id}" }

    context "with a live content item" do
      let!(:live_content_item) {
        FactoryGirl.create(:live_content_item,
          content_id: content_id,
          base_path: base_path,
        )
      }

      it "sends a message with a 'links' routing key" do
        expect(DownstreamService).to receive(:broadcast_to_message_queue).with(anything, 'links')
        patch request_path, params: request_body

        expect(response.status).to eq(200)
      end
    end

    context "with a draft content item" do
      let!(:draft_content_item) {
        FactoryGirl.create(:draft_content_item,
          content_id: content_id,
          base_path: base_path,
        )
      }

      it "doesn't send any messages" do
        expect(DownstreamService).to_not receive(:broadcast_to_message_queue)
        expect(PublishingAPI.service(:queue_publisher)).not_to receive(:send_message)

        patch request_path, params: request_body

        expect(response.status).to eq(200)
      end
    end
  end

  context "/v2/publish" do
    before do
      FactoryGirl.create(:draft_content_item,
        content_id: content_id,
        document_type: "guide",
        schema_name: "guide",
        base_path: base_path,
      )
    end

    it "sends a message with the 'document_type.update_type' routing key" do
      expect(DownstreamService).to receive(:broadcast_to_message_queue).with(anything, "major")
      post "/v2/content/#{content_id}/publish", params: { update_type: "major" }.to_json
      expect(response.status).to eq(200)
    end
  end
end
