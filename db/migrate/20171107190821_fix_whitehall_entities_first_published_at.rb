require "csv"

class FixWhitehallEntitiesFirstPublishedAt < ActiveRecord::Migration[5.1]
  def up
    count = 0
    start_datetime = "2016-02-29 09:24:09"
    end_datetime = "2016-02-29 09:24:11"

    data = CSV.read(
      Rails.root.join(
        "db", "migrate", "data", "whitehall_entities_first_published_at.csv"
      )
    )

    data.each do |content_id, first_published_at|
      if first_published_at
        count += Edition
          .joins(:document)
          .where("first_published_at BETWEEN '#{start_datetime}' AND '#{end_datetime}'")
          .where(
            publishing_app: "whitehall",
            "documents.content_id": content_id
          )
          .update_all(first_published_at: first_published_at)
      end
    end

    puts "#{count} editions updated."
  end
end
