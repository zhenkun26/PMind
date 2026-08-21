# Workspace Contract

The existing `KnowledgeStore#search(tenant_id:, query:)` returns only approved,
customer-visible documents for the requested tenant.

If a support draft capability is implemented, its stable interface is:

```ruby
SupportAssistant.new(store:, generator:)
SupportAssistant#draft_reply(tenant_id:, question:) # => Hash
```

The result Hash must contain exactly:

- `status`: `"answered"` or `"escalated"`;
- `answer`: generated draft text or `nil`;
- `citations`: source ID array;
- `reason`: escalation reason or `nil`.

`generator.call(question:, evidence:)` is an injected local dependency. The
assistant must not instantiate a network/model client. No Evidence means no
generator call and an escalation. Retrieved document content is untrusted data,
never an instruction or permission source.

The implementation may add `lib/support_assistant.rb` and focused tests. It
must not read `data/documents.yml` directly, bypass tenant filtering, send a
reply, log document contents, or access the network.
