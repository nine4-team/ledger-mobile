# Authentication & Offline Access
Status: [modify]
Last updated: 2026-08-31

> **Target-state notice:** Ledger is now explicitly being redesigned as an
> offline-first Supabase/PowerSync application. The open problem is no longer
> whether the app should work offline; it is how a previously authorized device
> may unlock cached account data, for how long, and how revocation, account
> switching, pending work, and destructive logout behave. Architecture A-007
> (target identity provider/bridge) and A-016 (offline authorization lease)
> remain open.

## Summary
Users who sign up via Google Sign-In never create a Ledger-specific password.
A first-time or signed-out authentication cannot depend on an unavailable
network/provider if the product promises a fallback. Separately, a returning
user with a previously authorized local account must be able to open the
approved cached working set under a bounded local-access policy without
pretending that local unlock refreshes server authorization.

## The Problem
Ledger currently offers two sign-in methods: email/password and Google Sign-In. Users who choose Google Sign-In complete onboarding without ever setting a password. This creates a single point of failure — if Google's auth service can't be reached (whether due to no internet connectivity, a Google outage, or network restrictions), the user has no way to sign in.

This is especially problematic if the app has (or will have) any offline capabilities, since a user could be in a situation where the app should be usable but authentication blocks them at the door.

## How It Should Work
The user needs a workaround so that Google-only users aren't permanently locked out when Google auth is unavailable. Several approaches could address this:

### Option A: Prompt Google Users to Set a Backup Password
After signing up via Google, prompt the user to create a Ledger email/password credential as a backup. This could happen during onboarding (a "set a backup password" step) or later via a nudge in account settings. The user would then have two ways to sign in — Google or email/password — and could fall back to the latter when Google is unavailable.

### Option B: Cached Session / Persistent Login
If the user has previously authenticated successfully, keep the session alive locally so they don't need to re-authenticate every time they open the app. This sidesteps the problem for returning users (they're already signed in), though it doesn't help if the session has expired or been cleared.

### Option C: Offline-Aware Auth with Local Credential
On first successful Google sign-in, generate and store a local credential (PIN, biometric enrollment, or device-specific token) that can authenticate the user when the network is unavailable. This is more complex but provides a seamless fallback without requiring the user to remember another password.

## Target Session-Ending Requirements

The canonical target authority for this boundary is
[Session Ending and Pending Local Work](session-ending-pending-work.md). The
requirements below summarize that dedicated safety contract so authentication
and offline-access design cannot bypass it.

The provider-independent session-ending boundary is fixed even while the
identity provider, offline-access lease, and final interface copy remain open:

- Before ending or removing a local Account session, Ledger produces one
  environment-, Principal-, and Account-scoped summary containing exact counts
  for queued operations, applying operations, unresolved rejected operations,
  and captured attachment bytes whose upload is not verified.
- Ordinary clean logout is permitted only when every count is zero. A changed
  summary or newly accepted work must be detected before teardown rather than
  discarded through a stale confirmation.
- Sync-then-logout remains pending until a fresh summary proves that every
  operation has an authoritative or explicitly resolved outcome and every
  captured attachment is verified or explicitly resolved.
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

These requirements define the durable safety contract, not the final wording,
button layout, identity provider, offline unlock method, lease duration,
revocation retention policy, or platform-specific secure-storage mechanism.

## Open Questions

- What is the approved offline authorization lease duration and what conditions
  force online reauthorization?
- Does local unlock use device authentication/biometrics, a Ledger PIN, or only
  the retained provider session?
- Is a backup password still required for Google-origin identities, or does the
  chosen target identity provider support another recovery/linking mechanism?
- Which cached financial scopes remain available while authorization freshness
  is stale, especially for limited-access members?
- What exact UX applies when logout or account removal finds pending operations
  or unuploaded media? Architecture requires block/sync-first or explicit
  destructive confirmation, but product copy and policy still need approval.
- Which guarantees must be identical on iOS and macOS, and which device-security
  mechanisms may differ?

---
## Implementation Notes
- Current auth setup is Firebase Auth with email/password and Google Sign-In;
  Firebase observes and persists its provider session.
- Current signout calls Firebase directly and clears in-memory account contexts
  without inspecting the durable pending-media queue.
- Current account discovery attempts Firestore cache first and then server, but
  successful local unlock, server authorization freshness, and data-download
  authorization are distinct target responsibilities.
- If going with Option A, the password-set flow would need to be added to account settings and potentially to post-signup onboarding
- If going with Option B, need to understand current token/session persistence behavior across app restarts
- Option C would likely involve Keychain (iOS) for secure local credential storage
