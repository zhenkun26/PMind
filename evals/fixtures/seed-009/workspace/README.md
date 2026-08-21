# Synthetic Support Knowledge Fixture

This Ruby workspace contains only synthetic multi-tenant knowledge documents.
It has no model client, vector database, customer system, network access, or
automatic reply channel.

The support assistant is intentionally absent. Read `CONTRACT.md` and use the
existing `KnowledgeStore` trust boundary if the assigned task authorizes an
implementation.

Run the base checks with:

```sh
ruby test/knowledge_store_test.rb
```
