# Proof retention operations

The service starts its cleanup worker automatically. No external cron job or
extra dependency is required. See [VM-011](user-journeys/proof-recipient.md#vm-011---end-access-and-remove-retained-proof-data)
for the deletion policy and limits. Existing `deleted_at` columns implement
retryable claims, so this change requires no schema migration.

Monitor the aggregate `Proof retention cleanup` log counts. A nonzero `failed`
count or `cleanup failed; will retry` requires checking database/object-storage
availability. Logs deliberately omit proof IDs, ciphertext, URLs and keys.
Cleanup resumes after restart; a backlog drains in bounded batches. S3 deletion
has a ten-second request deadline. Keep presigned upload validity below the
24-hour cleanup grace interval.

## Erasure requests

Never ask for the private URL fragment, message text, original audio, or a
private signing key. A public proof ID/slug identifies the record but does not
authorize deletion. The author can authorize revocation using the existing
`POST /v1/proofs/{slug}/revoke` endpoint with the revocation capability retained
by their Mac. Treat that capability as a secret; do not place it in logs, email,
issues or shell history. After authorized revocation, normal cleanup removes the
live object, record and alias. Requests without a capability require a separate
ownership check; knowing a public link is insufficient.

For installation-key erasure, verify control through the existing signed
challenge mechanism before performing an operator-managed deletion. Review
linked proofs and tell the requester which shared links will become unavailable.
Do not delete an installation merely because it has been inactive: the native
app retains its installation ID. Keep any case evidence outside the public repo.

## Backups and restores

Live cleanup does not erase historical backups. Inventory the actual Coolify,
volume and database snapshots before promising a backup-deletion date. Restrict
access and keep an explicit bounded retention schedule in private operations
records. Before returning a restored backup to public traffic, reconcile
revocations/deletions recorded after that backup and run cleanup to completion.
If that reconciliation is unavailable, do not serve restored proofs. A database
backup containing revocation hashes is sensitive even without message keys.

## Local database verification

Use an isolated disposable PostgreSQL database, never a production URL:

```sh
DATABASE_URL=postgresql://postgres@127.0.0.1:55439/hush_test bun run db:migrate
HUSH_TEST_DATABASE_URL=postgresql://postgres@127.0.0.1:55439/hush_test bun test server/services/proof-cleanup.test.ts
```

Normal `bun test server` runs the SQLite/filesystem contract. Both use synthetic
proofs. Do not attach production data to test reports.
