# Handoff

## Objective
Make failed card charges retry automatically instead of dropping the order. Done when a
declined charge is retried on the documented schedule, a permanently failed charge moves the
order to `payment_failed`, and no charge is ever attempted twice for the same attempt id.

## Completed
- `src/billing/retry.ts` — retry scheduler, backoff table, and the idempotency key derivation.
- `src/billing/webhooks.ts` — `charge.failed` now enqueues a retry instead of finalising the order.
- Migration `0042_add_charge_attempts.sql` — new `charge_attempts` table, applied on the dev
  database only.

Implemented, not yet verified: the scheduler has never run against the sandbox gateway.

## Decisions and Rationale
- Idempotency key is `order_id + attempt_number`, not a UUID, so a retry after a crash reuses the
  same key and the gateway de-duplicates for us.
- Backoff lives in a table in code, not in the database. The schedule is policy the business
  states, and a finite table is exactly the kind of thing code should own.
- Hard cap of 4 attempts. Chosen with the finance owner on 2026-01-30; do not raise it without
  asking them.

## Relevant / Changed Files
- `src/billing/retry.ts` — `scheduleRetry()`, `nextDelayMs()`. The whole feature is here.
- `src/billing/webhooks.ts` — `handleChargeFailed()`. The only caller.
- `migrations/0042_add_charge_attempts.sql` — not applied to staging or production.
- `src/billing/gateway.ts` — untouched, but `charge()` is the function the retry calls; read it
  before changing the key derivation.

## Remaining Work
1. Run the scheduler against the sandbox gateway and confirm a declined card produces exactly
   four attempts.
2. Apply migration 0042 to staging.
3. Add the `payment_failed` transition to the order state machine — currently the order stays
   `pending` forever after the last attempt.
4. Alert on the retry queue depth.

## Known Issues / Open Questions
- `nextDelayMs()` has no jitter. With a batch of failures from one gateway outage, all retries
  fire in the same second. Probably needs jitter before this reaches production.
- Unclear whether the gateway's own automatic retries overlap with ours. Nobody has read that
  part of their docs yet.

## Rejected / Superseded Approaches
- A cron job scanning for failed charges. Rejected: it cannot see attempt ordering, so a crash
  mid-retry produced duplicate charges in testing.
- Storing the backoff schedule in the database. Rejected: it made a policy change a deploy plus a
  migration, with no gain.

## Verification State
`npm test` (the registered check) was last run after the webhook change and passed. The billing
integration suite has not been run since migration 0042 was added. Nothing has been run against
the sandbox gateway.

## Completion Verification
`npm test`, then `npm run test:integration -- billing`, then a manual sandbox run with the
gateway's declined-card test number showing four attempts and a final `payment_failed` order.

## Recommended Next Action
Run the billing integration suite. It is the fastest way to find out whether migration 0042
broke anything before spending time on the sandbox gateway.
