# Session Ending and Pending Local Work

Status: canonical target safety contract
Last updated: 2026-09-02

## Purpose

Ledger is offline-first. A locally accepted operation or captured attachment is
real user work even before the server applies or verifies it. Ending a session
must therefore be an explicit durability workflow, not a direct identity-
provider signout followed by unconditional local deletion.

This spec owns only session-ending loss prevention. Identity-provider choice,
offline unlock and authorization lease, final interface copy/layout,
revocation-retention policy, platform secure storage, and physical adapter
implementation remain governed by their named open decisions and architecture
gates.

## Session-Ending Safety Contract

- Before ending or removing a local Account session, Ledger produces one
  environment-, Principal-, and Account-scoped summary containing exact counts
  for queued operations, applying operations, unresolved rejected operations,
  and captured attachment bytes whose upload is not verified.
- Ordinary clean logout is permitted only when every count is zero. A changed
  summary or newly accepted work must be detected before teardown rather than
  discarded through a stale decision.
- Sync-then-logout remains pending until a fresh same-scope summary proves that
  every operation has an authoritative or explicitly resolved outcome and
  every captured attachment is verified or explicitly resolved.
- Destructive local removal is the only path that may discard pending work. It
  requires an explicit confirmation bound to the exact scoped summary and exact
  counts currently being removed; a changed summary invalidates confirmation.
  This path never claims discarded work reached the server.
- Cancellation creates no session-ending request. Provider signout, sync
  shutdown, queue/media deletion, database/key removal, cache cleanup, and
  cleanup recovery are coordinated behind the session-ending boundary rather
  than being callable independently by a feature screen.
- App termination, token expiry, revocation, a closed prompt, or interrupted
  cleanup is never destructive consent. Cleanup resumes fail-closed before the
  same Principal's protected local data may be reopened.

## Non-Authority and Open Decisions

This contract does not choose or imply:

- Firebase Auth, Supabase Auth, an Auth bridge, or any other identity provider;
- an offline authorization duration, biometric/PIN policy, or reauthentication
  trigger (A-007/A-016 remain open);
- final warning text, button layout, default choice, or platform presentation;
- whether attachment bytes may be detached, retained, quarantined, or purged
  under O-023;
- a database, encryption/key, filesystem, cache, upload, or provider-signout
  implementation; or
- migration, hosted-resource, production, release, or cutover authority.

## Acceptance Outcomes

- clean logout evaluates ready only from a fresh all-zero same-scope summary;
- any pending class blocks ordinary logout;
- sync-first remains incomplete until a fresh all-zero same-scope summary;
- destructive removal requires exact current-summary confirmation and refuses
  after any scope, count, or summary revision change;
- cancel performs no end-session call;
- malformed, rebound, stale, or interrupted evidence fails closed; and
- no target-neutral test claims that bytes/data were actually uploaded,
  deleted, synchronized, or signed out.
