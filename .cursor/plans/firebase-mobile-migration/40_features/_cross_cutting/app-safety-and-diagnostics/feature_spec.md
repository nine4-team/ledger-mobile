# App Safety + Diagnostics (Cross-cutting)

This feature captures the minimal safety items still needed, without building
any large diagnostics or recovery system.

## Goals (minimal scope)

- Provide a global error boundary with a simple fallback UI.
- Offer a "safe mode" screen for fatal startup failures.
- Keep diagnostics lightweight (dev-only export, minimal logging).

## Non-goals (explicit)

- Rebuilding the app foundation (auth bootstrap, nav shell, etc.).
- Building a large diagnostics platform or support tooling.
- Adding complex recovery flows beyond retry/reset.
- Defining offline banners/sync status UI (see `40_features/connectivity-and-sync-status/`).
- Implementing conflict resolution flows (owned by domain features).

## Requirements

### Global error boundary (minimum viable)

- Register a top-level error boundary at the root of the app.
- Fallback UI should:
  - show a simple message
  - allow a retry
  - optionally allow log export in dev builds

### Safe mode for fatal init failures (narrow triggers)

- If startup fails (e.g. corrupted local state, migration failure), enter safe mode.
- Safe mode should:
  - block normal navigation
  - show a clear recovery path (retry / reset local cache)
  - record a minimal diagnostic event

### Diagnostics + logging (lightweight)

- Log only what is necessary for debugging boot failures:
  - app start
  - error-boundary crash
  - safe-mode entry
  - local cache reset attempt/result
- Provide a simple log export affordance in dev builds (optional).

### Conflict indicator + resolution entry point (defer)

- Defer to domain features if/when conflict UX is needed.

## Integration points (keep small)

- **Connectivity + sync status**: keep banners and retry UX in
  `40_features/connectivity-and-sync-status/`.
- **Request-doc workflows**: only if a feature explicitly needs conflict UX.

