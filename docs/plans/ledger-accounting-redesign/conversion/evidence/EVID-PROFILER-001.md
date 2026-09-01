# EVID-PROFILER-001 — Fail-Closed Firebase Source Profilers

- Timestamp: 2026-08-31
- Class: source characterization tooling
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Exact target: Firebase project `ledger-nine4`, account
  `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`, and Storage bucket
  `ledger-nine4.firebasestorage.app`
- Production reads or mutations: none
- Operator: Codex

## Implemented Boundaries

The Firestore/Auth and Storage profilers are separate entry points with a
shared fail-closed runtime. Both require explicit project, account, external
credential file, fixed gitignored output directory, `--execute-read-only`, and
the exact confirmation token. The Storage profiler additionally requires the
exact bucket.

The runtime refuses emulator variables, another project/account/bucket, a
missing or repository-local credential, group/world credential permissions,
non-service-account credentials, and service-account keys for another project.
Artifacts are aggregate/redacted JSON with payload and file hashes. They omit
document IDs, UIDs, emails, object names, URLs, arbitrary string values, and
object-content hashes. Storage bytes are never downloaded.

## Verification

```bash
node --check scripts/lib/firebase-readonly-profile.mjs
node --check scripts/check-firebase-readonly-profilers.mjs
node --check scripts/profile-firebase-firestore-auth-readonly.mjs
node --check scripts/profile-firebase-storage-readonly.mjs
npm run conversion:profiles:check-readonly
node scripts/profile-firebase-firestore-auth-readonly.mjs --help
node scripts/profile-firebase-storage-readonly.mjs --help
node scripts/profile-firebase-firestore-auth-readonly.mjs \
  --project ledger-nine4 \
  --account 1dd4fd75-8eea-4f7a-98e7-bf45b987ae94 \
  --credential-file /definitely/missing.json \
  --output-dir migration/out/source-profiles
```

Syntax, mutation guard, help, and the intentional missing-credential refusal
passed. The source check reports no recognized Firebase mutation API in the
profile runtime.

The local negative gate matrix also passed: the entry points refused the
available authorized-user ADC, a different project, an enabled Firestore
emulator variable, an output directory outside the fixed profile directory,
and a different Storage bucket. These refusals occur before Firebase Admin
initialization, so they made no remote calls.

## Credential Resolution and Blocker

This host has no `GOOGLE_APPLICATION_CREDENTIALS` setting and no acceptable
service-account key was found through the configured path. It has a chmod-600
Google authorized-user ADC whose quota project is `n4-1584-design-tools`, while
the active gcloud project is `ledger-nine4`. The profiler intentionally rejects
that ADC because it cannot prove a service-account identity/project from the
credential file before remote access.

Therefore no preflight using a qualifying credential and no production profile
was run. The next operator action is to provide an external chmod-600
service-account JSON whose `project_id` is exactly `ledger-nine4`, then run
preflight before repeating with the exact read-only confirmation token. This is
a credential blocker, not permission to weaken the gate or mutate production.
