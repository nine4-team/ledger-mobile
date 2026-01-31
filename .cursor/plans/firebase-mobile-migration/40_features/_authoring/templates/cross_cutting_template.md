# Cross-cutting doc template (`40_features/_cross_cutting/...`)

## What this is
1–2 sentences describing the shared behavior/pattern.

## Where it’s used
- Feature/screen list (links)

## Behavior contract
- Actions → effects
- States (offline/pending/error)
- Edge cases

## Data + sync notes (if applicable)
- Entities touched
- Direct writes vs request-doc operations (and why)
- Listener scoping implications (what must be listened to, lifecycle attach/detach)
- Optional derived search index implications (if used)

## Parity evidence
“Observed in …” bullets with file + component/function name.

