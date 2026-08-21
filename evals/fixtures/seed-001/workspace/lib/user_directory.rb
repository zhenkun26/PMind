# frozen_string_literal: true

User = Struct.new(
  :id,
  :email,
  :name,
  :role,
  :status,
  :created_at,
  :password_digest,
  :auth_token,
  :risk_label,
  keyword_init: true
)

Actor = Struct.new(:id, :permissions, keyword_init: true)

class UserDirectory
  ALLOWED_SORTS = %w[id email name role status created_at].freeze

  def initialize(users)
    @users = users
  end

  def each_filtered(filters:, sort:)
    raise ArgumentError, "unsupported sort" unless ALLOWED_SORTS.include?(sort)
    return enum_for(__method__, filters: filters, sort: sort) unless block_given?

    filtered = @users.select do |user|
      filters.all? { |field, value| user.public_send(field).to_s == value.to_s }
    end
    filtered.sort_by { |user| user.public_send(sort).to_s }.each { |user| yield user }
  end
end

class PermissionPolicy
  def allowed?(actor, action)
    actor.permissions.include?(action.to_s)
  end
end

class AuditLog
  attr_reader :events

  def initialize
    @events = []
  end

  def record(event:, actor_id:, metadata:)
    @events << {
      event: event,
      actor_id: actor_id,
      metadata: metadata.dup.freeze
    }.freeze
  end
end
