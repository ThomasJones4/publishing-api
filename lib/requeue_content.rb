class RequeueContent
  def initialize(scope)
    # Restrict scope to stuff that's live (published or unpublished)
    # Unpublished content without a content store representation won't
    # be returned, but we're not interested in this content.
    @scope = scope.where(content_store: :live)
    @version = Event.maximum(:id)
  end

  def call
    scope.find_each do |edition|
      publish_to_queue(edition)
    end
  end

private

  attr_reader :scope, :version

  def publish_to_queue(edition)
    presenter = DownstreamPayload.new(edition, version, draft: false)
    queue_payload = presenter.message_queue_payload
    service = PublishingAPI.service(:queue_publisher)

    # Requeue is considered a different event_type to major, minor etc
    # because we don't want to send additional email alerts to users.
    if edition.base_path == '/hmrc-internal-manuals/inheritance-tax-manual/ihtm34071'
      service.send_message(
        queue_payload,
        routing_key: "#{edition.schema_name}.bulk.reindex",
        persistent: false
      )
    end
  end
end
