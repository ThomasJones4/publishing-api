module Commands
  module V2
    class PutContent < BaseCommand
      def call
        PutContentValidator.new(payload, self).validate
        prepare_content_with_base_path

        edition = create_or_update_edition
        update_content_dependencies(edition)

        after_transaction_commit do
          send_downstream(document.content_id, document.locale)
        end

        Success.new(present_response(edition))
      end

      def document
        @document ||= Document.find_or_create_locked(
          content_id: payload.fetch(:content_id),
          locale: payload.fetch(:locale, Edition::DEFAULT_LOCALE),
        )
      end

    private

      def content_with_base_path?
        base_path_required? || payload.has_key?(:base_path)
      end

      def prepare_content_with_base_path
        return unless content_with_base_path?
        PathReservation.reserve_base_path!(payload[:base_path], payload[:publishing_app])
        clear_draft_items_of_same_locale_and_base_path
      end

      def update_content_dependencies(edition)
        create_redirect
        access_limit(edition)
        update_last_edited_at(edition, payload[:last_edited_at])
        ChangeNote.create_from_edition(payload, edition)
        Action.create_put_content_action(edition, document.locale, event)
        create_links
      end

      def create_links
        payload.fetch(:links, []).each do |link_type, target_link_ids|
          links.each do |target_link_id|
            Link.create!(link_type: link_type, target_content_id: target_link_id, edition: edition)
          end
        end
      end

      def create_redirect
        return unless content_with_base_path?
        RedirectHelper::Redirect.new(previously_published_item,
                                     @previous_item,
                                     payload, callbacks).create
      end

      def present_response(edition)
        Presenters::Queries::ContentItemPresenter.present(
          edition,
          include_warnings: true,
        )
      end

      def access_limit(edition)
        if payload[:access_limited]
          AccessLimit.find_or_create_by(edition: edition).tap do |access_limit|
            access_limit.update_attributes!(
              users: (payload[:access_limited][:users] || []),
              fact_check_ids: (payload[:access_limited][:fact_check_ids] || []),
            )
          end
        else
          AccessLimit.find_by(edition: edition).try(:destroy)
        end
      end

      def create_or_update_edition
        if previously_drafted_item
          updated_item, @previous_item = UpdateExistingDraftEdition.new(previously_drafted_item, self, payload).call
        else
          new_draft_edition = CreateDraftEdition.new(self, payload, previously_published_item).call
        end
        updated_item || new_draft_edition
      end

      def previously_published_item
        @previously_published_item ||= PreviouslyPublishedItem.new(
          document, payload[:base_path], self
        ).call
      end

      def base_path_required?
        !Edition::EMPTY_BASE_PATH_FORMATS.include?(payload[:schema_name])
      end

      def previously_drafted_item
        document.draft
      end

      def clear_draft_items_of_same_locale_and_base_path
        SubstitutionHelper.clear!(
          new_item_document_type: payload[:document_type],
          new_item_content_id: document.content_id,
          state: "draft",
          locale: document.locale,
          base_path: payload[:base_path],
          downstream: downstream,
          callbacks: callbacks,
          nested: true,
        )
      end

      def update_last_edited_at(edition, last_edited_at = nil)
        if last_edited_at.nil? && %w(major minor).include?(payload[:update_type])
          last_edited_at = Time.zone.now
        end

        edition.update_attributes(last_edited_at: last_edited_at) if last_edited_at
      end

      def bulk_publishing?
        payload.fetch(:bulk_publishing, false)
      end

      def send_downstream(content_id, locale)
        return unless downstream

        queue = bulk_publishing? ? DownstreamDraftWorker::LOW_QUEUE : DownstreamDraftWorker::HIGH_QUEUE

        DownstreamDraftWorker.perform_async_in_queue(
          queue,
          content_id: content_id,
          locale: locale,
          payload_version: event.id,
          update_dependencies: true,
        )
      end
    end
  end
end
