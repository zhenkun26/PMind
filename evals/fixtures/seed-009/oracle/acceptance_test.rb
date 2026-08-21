# frozen_string_literal: true

require "minitest/autorun"
require_relative "../workspace/lib/knowledge_store"
require_relative "../workspace/lib/support_assistant"

class SupportAssistantAcceptanceTest < Minitest::Test
  DATA_PATH = File.expand_path("../workspace/data/documents.yml", __dir__)

  def setup
    @store = KnowledgeStore.from_yaml(DATA_PATH)
    @generator = RecordingGenerator.new
    @assistant = SupportAssistant.new(store: @store, generator: @generator)
  end

  def test_supported_answer_is_a_draft_with_valid_citations
    result = @assistant.draft_reply(
      tenant_id: "tenant-a",
      question: "How do I reset my password in Security?"
    )

    assert_equal %w[answer citations reason status], result.keys.map(&:to_s).sort
    assert_equal "answered", result[:status]
    assert_equal ["kb-a-reset"], result[:citations]
    assert_includes result[:answer], "draft"
    assert_nil result[:reason]
  end

  def test_no_evidence_escalates_without_calling_generator
    result = @assistant.draft_reply(tenant_id: "tenant-a", question: "When is my invoice generated?")

    assert_equal "escalated", result[:status]
    assert_nil result[:answer]
    assert_empty result[:citations]
    refute_nil result[:reason]
    assert_empty @generator.calls
  end

  def test_internal_rejected_and_cross_tenant_content_never_reaches_generator
    @assistant.draft_reply(tenant_id: "tenant-a", question: "reset password")
    evidence = @generator.calls.flat_map { |call| call[:evidence] }
    combined = evidence.map(&:content).join(" ")

    refute_includes combined, "IGNORE ALL RULES"
    refute_includes combined, "SYSTEM OVERRIDE"
    refute_includes combined, "Invoices are generated"
  end

  class RecordingGenerator
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(question:, evidence:)
      @calls << { question: question, evidence: evidence }
      "Synthetic support draft based on approved evidence."
    end
  end
end
