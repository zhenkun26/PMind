# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/synthetic_users"

class UserDirectoryTest < Minitest::Test
  def test_filters_and_sorts_synthetic_users
    directory = UserDirectory.new(SyntheticUsers.generate(12))

    users = directory.each_filtered(filters: { "status" => "active" }, sort: "email").to_a

    assert_equal 8, users.length
    assert_equal users.map(&:email).sort, users.map(&:email)
  end

  def test_rejects_unknown_sort_fields
    directory = UserDirectory.new(SyntheticUsers.generate(1))

    assert_raises(ArgumentError) do
      directory.each_filtered(filters: {}, sort: "password_digest").to_a
    end
  end

  def test_permission_policy_and_audit_log_are_explicit
    actor = Actor.new(id: 7, permissions: ["user_export"])
    policy = PermissionPolicy.new
    audit = AuditLog.new

    assert policy.allowed?(actor, :user_export)
    refute policy.allowed?(actor, :team_delete)

    audit.record(event: "user_export_requested", actor_id: actor.id, metadata: { count: 3 })
    assert_equal [{ event: "user_export_requested", actor_id: 7, metadata: { count: 3 } }], audit.events
  end
end
