module Queries
  class KeysetPagination
    attr_reader :client, :order, :key, :count, :previous

    # Initialises the keyset pagination class.
    # Params:
    # +client+:: the pagination client to query over
    # +key+:: +Hash+ a hash containing the pagination key, mapped from presented name to internal name, i.e. { id: "editions.id" }
    # +order+:: +Symbol+ either :asc for ascending and :desc for descending
    # +count+:: +Fixnum+ the number of records to return in each page
    # +after+:: +Array+ the current page to paginate after, an array containing a value for each field in the key
    def initialize(client, key: nil, order: nil, count: nil, before:, after:)
      @client = client
      @key = key || { id: "id" }
      @order = order || :asc
      @count = (count || 100).to_i

      if before.present? && after.present?
        raise "Before and after cannot both be present."
      end

      if before
        @previous = before
        @order = order == :asc ? :desc : :asc
        @direction = :backwards
      else
        @previous = after
        @direction = :forwards
      end

      if previous.present? && previous.count != key.count
        raise "Number of previous values does not match the number of fields."
      end
    end

    def call
      results
    end

    def next_before_key
      key_for_record(results.first)
    end

    def next_after_key
      key_for_record(results.last)
    end

    def has_next_before?
      KeysetPagination.new(
        client, key: key, order: order, count: 1,
        before: next_before_key, after: nil
      ).call.count >= 1
    end

    def has_next_after?
      KeysetPagination.new(
        client, key: key, order: order, count: 1,
        before: nil, after: next_after_key
      ).call.count >= 1
    end

  private

    attr_reader :direction

    def results
      ordered_results
    end

    def key_for_record(record)
      key.keys.map do |k|
        value = record[k.to_s]
        next value.iso8601 if value.respond_to?(:iso8601)
        value.to_s
      end
    end

    def pluck_to_hash(query, keys)

    end

    def ordered_results
      if direction == :backwards
        plucked_results.reverse
      else
        plucked_results
      end
    end

    def plucked_results
      paginated_query.pluck(*fields).map do |record|
        Hash[fields.zip(record)]
      end
    end

    def fields
      @fields ||= (client.fields + key.keys).uniq.map(&:to_s)
    end

    def paginated_query
      paginated_query = client.call.order(order_clause)
      paginated_query = paginated_query.where(where_clause, *previous) if previous
      paginated_query.limit(count)
    end

    def ascending?
      order == :asc
    end

    def order_clause
      key.keys.each_with_object({}) { |field, hash| hash[field] = order }
    end

    def order_character
      ascending? ? ">" : "<"
    end

    def where_clause_lhs
      key.values.join(", ")
    end

    def where_clause_rhs
      (["?"] * key.count).join(", ")
    end

    def where_clause
      "(#{where_clause_lhs}) #{order_character} (#{where_clause_rhs})"
    end
  end
end
