# [Feature Name]

## Purpose
One sentence on what this feature does for the user.

## Files
Key files across layers and what each does. Skip files whose purpose is obvious from the name.

- `Views/` —
- `State/` —
- `Services/` —
- `Logic/` —
- `Components/` — (feature-specific only; shared components go in root CLAUDE.md)

## State
Which @Observable store(s) own this feature's state. Who creates them and where they're injected.

## Data
Firestore collections read/written. Document path patterns (e.g., `users/{uid}/projects/{projectId}/items`) and any non-obvious field mappings or legacy migrations.

## Sheets & Navigation
Sheet triggers, detent sizes, dismissal patterns, and any sheet sequencing rules specific to this feature.

## Gotchas
Anything that bit us or would surprise a future developer. Non-obvious constraints, ordering requirements, known quirks.
