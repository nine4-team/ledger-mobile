# Authentication & Offline Access
Status: [tbd]
Last updated: 2026-04-05

## Summary
Users who sign up via Google Sign-In never create a Ledger-specific password. If the app is used in a scenario where Google's authentication service is unavailable (no internet, Google outage, etc.), those users are locked out entirely. A fallback authentication method is needed so Google-only users can still access the app.

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

## Open Questions

- **Does the app currently work offline at all?** If not, this may be a moot point until offline support is added — but it's still worth solving for Google outages and flaky connections. Needs confirmation from the dev team.
- **How long do sessions last?** If users stay logged in indefinitely (Option B behavior), the lockout scenario may be rare in practice. Need to understand current session/token expiration behavior.
- **Which option does the team prefer?** Option A (backup password) is the simplest to implement. Option B (persistent session) may already partially exist. Option C (local credential) is the most robust but most complex.
- **Is this iOS-only or does it affect the web and desktop apps too?** The web app obviously requires internet regardless, but the desktop app (macOS) could have similar offline concerns.

---
## Implementation Notes
- Current auth setup: email/password and Google Sign-In coexist as sign-in options
- Need to understand the current auth stack (Firebase Auth? Custom?) to assess feasibility of each option
- If going with Option A, the password-set flow would need to be added to account settings and potentially to post-signup onboarding
- If going with Option B, need to understand current token/session persistence behavior across app restarts
- Option C would likely involve Keychain (iOS) for secure local credential storage
