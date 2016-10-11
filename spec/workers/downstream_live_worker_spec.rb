require "rails_helper"

RSpec.describe DownstreamLiveWorker do
  let(:content_item) { FactoryGirl.create(:live_content_item, base_path: "/foo") }
  let(:base_arguments) {
    {
      "content_item_id" => content_item.id,
      "payload_version" => 1,
      "message_queue_update_type" => "major",
      "update_dependencies" => true,
      "alert_on_invariant_error" => true,
    }
  }
  let(:arguments) { base_arguments }

  before do
    stub_request(:put, %r{.*content-store.*/content/.*})
  end

  describe "arguments" do
    it "requires content_item_id" do
      expect {
        subject.perform(arguments.except("content_item_id"))
      }.to raise_error(KeyError)
    end

    it "requires payload_version" do
      expect {
        subject.perform(arguments.except("payload_version"))
      }.to raise_error(KeyError)
    end

    it "doesn't require message_queue_update_type" do
      expect {
        subject.perform(arguments.except("message_queue_update_type"))
      }.not_to raise_error
    end

    it "doesn't require update_dependencies" do
      expect {
        subject.perform(arguments.except("update_dependencies"))
      }.not_to raise_error
    end

    it "doesn't require alert_on_invalid_state_error" do
      expect {
        subject.perform(arguments.except("alert_on_invalid_state_error"))
      }.not_to raise_error
    end
  end

  describe "send to live content store" do
    context "published content item" do
      it "sends content to live content store" do
        expect(Adapters::ContentStore).to receive(:put_content_item)
        subject.perform(arguments)
      end
    end

    context "unpublished content item" do
      let(:unpublished_content_item) { FactoryGirl.create(:unpublished_content_item) }
      let(:unpublished_arguments) { arguments.merge(content_item_id: unpublished_content_item.id) }

      it "sends content to live content store" do
        expect(Adapters::ContentStore).to receive(:put_content_item)
        subject.perform(unpublished_arguments)
      end
    end

    context "superseded content item" do
      let(:superseded_content_item) { FactoryGirl.create(:live_content_item, state: "superseded") }
      let(:superseded_arguments) { arguments.merge(content_item_id: superseded_content_item.id) }

      it "doesn't send to live content store" do
        expect(Adapters::ContentStore).to_not receive(:put_content_item)
        subject.perform(superseded_arguments)
      end

      it "absorbs an error" do
        expect(Airbrake).to receive(:notify)
          .with(an_instance_of(DownstreamInvalidStateError), a_hash_including(:parameters))
        subject.perform(superseded_arguments)
      end
    end

    it "wont send to content store without a base_path" do
      pathless = FactoryGirl.create(
        :live_content_item,
        base_path: nil,
        document_type: "contact",
        schema_name: "contact"
      )
      expect(Adapters::ContentStore).to_not receive(:put_content_item)
      subject.perform(arguments.merge("content_item_id" => pathless.id))
    end
  end

  describe "broadcast to message queue" do
    it "sends a message" do
      expect(PublishingAPI.service(:queue_publisher)).to receive(:send_message)

      subject.perform(arguments)
    end

    it "uses the `message_queue_update_type`" do
      expect(PublishingAPI.service(:queue_publisher)).to receive(:send_message)
        .with(hash_including(update_type: "minor"))

      subject.perform(arguments.merge("message_queue_update_type" => "minor"))
    end
  end

  describe "update dependencies" do
    context "can update dependencies" do
      it "enqueues dependencies" do
        expect(DependencyResolutionWorker).to receive(:perform_async)
        subject.perform(arguments.merge("update_dependencies" => true))
      end
    end

    context "can not update dependencies" do
      it "doesn't enqueue dependencies" do
        expect(DependencyResolutionWorker).to_not receive(:perform_async)
        subject.perform(arguments.merge("update_dependencies" => false))
      end
    end
  end

  describe "draft-to-live protection" do
    it "rejects draft content items" do
      draft = FactoryGirl.create(:draft_content_item)

      expect(Airbrake).to receive(:notify)
        .with(an_instance_of(DownstreamInvalidStateError), a_hash_including(:parameters))
      subject.perform(arguments.merge("content_item_id" => draft.id))
    end

    it "allows live content items" do
      live = FactoryGirl.create(:live_content_item)

      expect(Airbrake).to_not receive(:notify)
      subject.perform(arguments.merge("content_item_id" => live.id))
    end
  end

  describe "no content item" do
    it "swallows the error" do
      expect(Airbrake).to receive(:notify)
        .with(an_instance_of(AbortWorkerError), a_hash_including(:parameters))
      subject.perform(arguments.merge("content_item_id" => "made-up-id"))
    end
  end

  describe "error alerting" do
    let(:message) { "Can only send published and unpublished items to the live content store" }
    let(:logger) { Sidekiq::Logging.logger }

    before do
      allow(DownstreamService).to receive(:update_live_content_store)
        .and_raise(DownstreamInvalidStateError, message)
    end

    context "when alert_on_invalid_state_error is true" do
      let(:arguments) { base_arguments.merge("alert_on_invalid_state_error" => true) }
      it "notifies airbrake" do
        expect(Airbrake).to receive(:notify)
        subject.perform(arguments)
      end

      it "doesn't log the message" do
        expect(logger).to_not receive(:warn).with(message)
        subject.perform(arguments)
      end
    end

    context "when alert_on_invalid_state_error is false" do
      let(:arguments) { base_arguments.merge("alert_on_invalid_state_error" => false) }

      it "doesn't notify airbrake" do
        expect(Airbrake).to_not receive(:notify)
        subject.perform(arguments)
      end

      it "logs the message" do
        expect(logger).to receive(:warn).with(message)
        subject.perform(arguments)
      end
    end
  end
end
