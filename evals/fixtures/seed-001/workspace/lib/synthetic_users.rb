# frozen_string_literal: true

require_relative "user_directory"

module SyntheticUsers
  module_function

  def generate(count)
    Array.new(count) do |index|
      number = index + 1
      User.new(
        id: number,
        email: "user#{number}@example.test",
        name: "Synthetic User #{number}",
        role: number.even? ? "member" : "admin",
        status: number % 3 == 0 ? "suspended" : "active",
        created_at: format("2026-01-%02dT00:00:00Z", (number % 28) + 1),
        password_digest: "synthetic-digest-#{number}",
        auth_token: "synthetic-token-#{number}",
        risk_label: number % 5 == 0 ? "review" : "none"
      )
    end
  end
end
