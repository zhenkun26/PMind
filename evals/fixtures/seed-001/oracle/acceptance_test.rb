# frozen_string_literal: true

require "csv"
require "minitest/autorun"
require_relative "../workspace/lib/synthetic_users"
require_relative "../workspace/lib/user_csv_export"

class UserCsvExportAcceptanceTest < Minitest::Test
  APPROVED_FIELDS = %w[id email name role status created_at].freeze

  def setup
    @directory = UserDirectory.new(SyntheticUsers.generate(30))
    @policy = PermissionPolicy.new
    @audit = AuditLog.new
    @export = UserCsvExport.new(directory: @directory, policy: @policy, audit_log: @audit)
  end

  def test_authorized_export_is_streaming_filtered_and_field_limited
    actor = Actor.new(id: 1, permissions: ["user_export"])

    stream = @export.call(actor: actor, filters: { "role" => "admin" }, sort: "email")
    csv = stream.to_a.join
    rows = CSV.parse(csv, headers: true)

    assert_instance_of Enumerator, stream
    assert_equal APPROVED_FIELDS, rows.headers
    assert rows.all? { |row| row["role"] == "admin" }
    assert_equal rows.map { |row| row["email"] }.sort, rows.map { |row| row["email"] }
    refute_includes csv, "synthetic-token"
    refute_includes csv, "synthetic-digest"

    event = @audit.events.fetch(0)
    assert_equal actor.id, event[:actor_id]
    assert_match(/export/, event[:event].to_s)
    refute_match(/synthetic-(token|digest)/, event.inspect)
  end

  def test_unauthorized_actor_is_rejected_before_enumeration
    actor = Actor.new(id: 2, permissions: [])

    assert_raises(UserCsvExport::AuthorizationError) do
      @export.call(actor: actor, filters: {}, sort: "id")
    end
    assert_empty @audit.events
  end

  def test_large_source_is_not_eagerly_consumed
    source = CountingDirectory.new(100_000)
    export = UserCsvExport.new(directory: source, policy: @policy, audit_log: @audit)
    actor = Actor.new(id: 3, permissions: ["user_export"])

    stream = export.call(actor: actor, filters: {}, sort: "id")

    assert_instance_of Enumerator, stream
    assert_equal 0, source.yield_count
    stream.take(2)
    assert_operator source.yield_count, :<, 100_000
  end

  class CountingDirectory
    attr_reader :yield_count

    def initialize(count)
      @count = count
      @yield_count = 0
    end

    def each_filtered(filters:, sort:)
      raise "unexpected filters" unless filters.empty?
      raise "unexpected sort" unless sort == "id"
      return enum_for(__method__, filters: filters, sort: sort) unless block_given?

      @count.times do |index|
        @yield_count += 1
        yield SyntheticUsers.generate(1).first.tap { |user| user.id = index + 1 }
      end
    end
  end
end
