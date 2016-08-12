class DownstreamLiveWorker
  attr_reader :content_item_id, :web_content_item, :payload_version, :message_queue_update_type, :update_dependencies

  include DownstreamQueue
  include Sidekiq::Worker
  include PerformAsyncInQueue

  sidekiq_options queue: HIGH_QUEUE

  def perform(args = {})
    assign_attributes(args.symbolize_keys)

    unless web_content_item
      raise AbortWorkerError.new("The content item for id: #{content_item_id} was not found")
    end

    payload = DownstreamPayload.new(web_content_item, payload_version, Adapters::ContentStore::DEPENDENCY_FALLBACK_ORDER)

    DownstreamService.update_live_content_store(payload) if web_content_item.base_path

    if web_content_item.state == "published"
      update_type = message_queue_update_type || web_content_item.update_type
      DownstreamService.broadcast_to_message_queue(payload, update_type)
    end

    enqueue_dependencies if update_dependencies
  rescue AbortWorkerError, DownstreamInvariantError => e
    Airbrake.notify_or_ignore(e, parameters: args)
  end

private

  def assign_attributes(attributes)
    @content_item_id = attributes.fetch(:content_item_id)
    @web_content_item = Queries::GetWebContentItems.find(content_item_id)
    @payload_version = attributes.fetch(:payload_version)
    @message_queue_update_type = attributes.fetch(:message_queue_update_type, nil)
    @update_dependencies = attributes.fetch(:update_dependencies, true)
  end

  def enqueue_dependencies
    DependencyResolutionWorker.perform_async(
      content_store: Adapters::ContentStore,
      fields: [:content_id],
      content_id: web_content_item.content_id,
      payload_version: payload_version,
    )
  end
end