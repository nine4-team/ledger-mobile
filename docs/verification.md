# Verification Profiles

Use the smallest profile that proves the change. State the profile before running Xcode tests, Firebase emulators, or any full suite.

## taxonomy-model

Use for category taxonomy, transaction model decoding, summary-shape, MCP schema, and Cloud Functions resolver changes that do not require live Firebase behavior.

Command:

```bash
./scripts/verify-taxonomy.sh
```

What it runs:

- `npm run build` in `firebase/functions`
- `npm run build` in `mcp-server`
- iOS app compile with the production `LedgeriOS` scheme
- focused Swift model tests only: `LedgeriOSTests/ModelCodableTests`

What it must not run:

- Firebase emulators
- `LedgeriOS (Emulator)` scheme
- full iOS test suite
- manual simulator app QA

Override the simulator only when needed:

```bash
IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.5' ./scripts/verify-taxonomy.sh
```

## firestore-integration

Use only when the changed behavior depends on Firebase Auth, Firestore rules, Storage, emulator seed data, snapshot listeners, or service calls that cannot be proven with pure model/unit tests.

Required preflight:

- Identify the exact integration test target(s) to run.
- Confirm the Firebase emulator stack required: Auth, Firestore, Storage, Functions.
- Confirm seed/import data path if required.
- Do not run the full iOS suite unless the change genuinely spans the suite.

Allowed tools:

- `LedgeriOS (Emulator)` scheme
- `firebase emulators:exec`
- focused integration tests named in the preflight

## release

Use only when shipping a release. Follow the `finish-him` skill, including release-specific verification, commit, push, TestFlight, Sparkle, and external tester steps as applicable.

Do not use release verification to validate ordinary model or taxonomy changes.
