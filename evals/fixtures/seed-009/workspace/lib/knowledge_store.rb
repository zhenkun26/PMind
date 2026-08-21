# frozen_string_literal: true

require "yaml"

KnowledgeDocument = Struct.new(
  :source_id,
  :tenant_id,
  :visibility,
  :publication_status,
  :title,
  :content,
  keyword_init: true
)

class KnowledgeStore
  def self.from_yaml(path)
    rows = YAML.safe_load(
      File.read(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    new(rows.map { |row| KnowledgeDocument.new(**symbolize(row)) })
  end

  def self.symbolize(row)
    row.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
  end
  private_class_method :symbolize

  def initialize(documents)
    @documents = documents.freeze
  end

  def search(tenant_id:, query:)
    query_tokens = tokenize(query)
    return [] if query_tokens.empty?

    eligible_documents(tenant_id).map do |document|
      score = (query_tokens & tokenize("#{document.title} #{document.content}")).length
      [score, document]
    end.select { |score, _document| score.positive? }
      .sort_by { |score, document| [-score, document.source_id] }
      .map(&:last)
  end

  private

  def eligible_documents(tenant_id)
    @documents.select do |document|
      document.tenant_id == tenant_id &&
        document.visibility == "customer" &&
        document.publication_status == "approved"
    end
  end

  def tokenize(text)
    text.downcase.scan(/[a-z0-9]+/).uniq
  end
end
