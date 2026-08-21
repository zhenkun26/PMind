# Workspace Contract

The existing application exposes:

- `UserDirectory#each_filtered(filters:, sort:)` for ordered user records;
- `PermissionPolicy#allowed?(actor, action)` for server-side authorization;
- `AuditLog#record(...)` for metadata-only audit events.

If an export is implemented, the stable interface must be:

```ruby
UserCsvExport.new(directory:, policy:, audit_log:)
UserCsvExport#call(actor:, filters:, sort:) # => Enumerator<String>
```

The implementation may add `lib/user_csv_export.rb` and focused tests. It must
not modify synthetic records to hide sensitive fields, weaken
`PermissionPolicy`, write files, access the network, or perform Git operations.

Errors must be explicit. An unauthorized actor must receive an authorization
error before any record is enumerated or audit success event is emitted.
