# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/knowledge_store"

class KnowledgeStoreTest < Minitest::Test
  DATA_PATH = File.expand_path("../data/documents.yml", __dir__)

  def setup
    @store = KnowledgeStore.from_yaml(DATA_PATH)
  end

  def test_returns_only_approved_customer_documents_for_tenant
    results = @store.search(tenant_id: "tenant-a", query: "reset password security")

    assert_equal ["kb-a-reset"], results.map(&:source_id)
    assert results.all? { |document| document.tenant_id == "tenant-a" }
    assert results.all? { |document| document.visibility == "customer" }
    assert results.all? { |document| document.publication_status == "approved" }
  end

  def test_does_not_leak_cross_tenant_or_unapproved_documents
    results = @store.search(tenant_id: "tenant-a", query: "billing override private incident")

    assert_empty results
  end

  def test_empty_query_has_no_evidence
    assert_empty @store.search(tenant_id: "tenant-a", query: "")
  end
end
