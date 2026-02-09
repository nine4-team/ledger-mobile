# Architecture Critique — Findings

Critique of Ledger Mobile architecture document, grounded in codebase exploration.

---

## Finding 1: Stale-Read Full-Form Overwrite (HIGH)

**What the doc says**: Edit screens "populate once, then user owns state." On save, write form values back (fire-and-forget) and navigate away. `setDoc` with `{ merge: true }` provides idempotency.

**What could go wrong**: `merge: true` only protects fields *not included in the write*. It does NOT protect against stale values for fields that ARE included. Every edit screen except Project Edit writes ALL form fields on every save — item edit writes `{ name, sku, source, status, purchasePriceCents, projectPriceCents, marketValueCents, notes, spaceId }`, transaction edit writes 12+ fields, budget category edit writes `{ name, metadata }`.

Concrete scenario: Designer A opens item edit at 9am (sees purchasePrice = $500). Designer B changes purchasePrice to $750 at 9:15am. Designer A edits only the item name at 9:30am and saves. The save writes `{ name: "New Name", purchasePriceCents: 50000, ... }` — silently reverting B's price change to $500. `merge: true` doesn't help because `purchasePriceCents` is in the payload.

This is NOT a concurrent-edit problem. It's a stale-read + full-form-overwrite problem. The 30-minute window makes it far more likely than true simultaneous edits.

**How likely**: Medium-high. Interior designers regularly open edit screens, get interrupted by a phone call or site visit, and come back later to finish. Two designers working on the same project's items is a normal workflow.

**Recommended action**: Two mitigations, either sufficient alone:

1. **Partial writes** (preferred): Only include changed fields in the save payload. Track which fields the user actually modified and write only those. This makes `merge: true` do what the doc thinks it does. Project Edit already does this for basic fields.
2. **Staleness detection**: On save, compare the form's original snapshot `updatedAt` with the current doc's `updatedAt`. If they differ, warn the user or merge. This is the "lightweight compare-before-commit" the doc explicitly rejects — but it only requires a single cache read, no server round-trip, and handles the stale-read case the doc doesn't acknowledge.

---

## Finding 2: Silent Security Rule Failures — Phantom Writes (HIGH)

**What the doc says**: Writes use `.catch(err => console.error(...))` with `trackPendingWrite()` for sync status visibility.

**What could go wrong**: When Firestore security rules reject a write, the native SDK applies it to the local cache anyway. The write queues for sync, gets rejected server-side, but the local cache retains the user's value. The user sees their edit, thinks it succeeded, and every other user sees the original value. There is no mechanism in the app to detect this divergence.

Concrete scenario: A user's account membership is downgraded from `admin` to `user` while they're offline. They edit a budget field (which requires admin). The edit applies locally. When they come online, the server rejects it — but the user still sees their value. They tell their team "I updated the budget to $10,000" and everyone else sees $8,000.

**How likely**: Low for the membership scenario. But security rule changes, rule bugs during deployment, or edge cases in rule logic could all trigger this. The app has no defense against it.

**Recommended action**: Accept the risk for MVP, but document it as a known limitation. For post-MVP: periodically re-read critical docs from server (`mode: 'online'`) to detect cache/server divergence. Alternatively, listen for Firestore's `hasPendingWrites` metadata on snapshots — if a doc has had pending writes for >30 seconds after connectivity returns, surface a warning.

---

## Finding 3: The Conflict Stance for Money Fields Is Correct — But for the Wrong Reason (MEDIUM)

**What the doc says**: Last-write-wins on `budgetCents`, `amountCents`, `purchasePriceCents` is acceptable because concurrent edits are rare in small teams.

**What the codebase reveals**: Budget totals (spent amounts) are **always computed client-side** from transaction data via `buildBudgetProgress()`. The `budgetCents` field on `ProjectBudgetCategory` is only the *planned* budget, not a running total. Item moves that affect budget spend go through request-docs (Tier 2) which update canonical transactions atomically.

**The real argument**: Last-write-wins on money fields is safe not primarily because concurrent edits are rare (they're not *that* rare — see Finding 1), but because:
- `budgetCents` is a user-entered planning number, not a derived total. Overwriting it is like overwriting a project name — annoying if wrong, but not data corruption.
- Actual spend is computed from transactions, which are managed atomically via request-docs.
- `purchasePriceCents` on items is source data, not derived. Two users editing the same item's price simultaneously is genuinely rare.

**The doc should say this.** The current argument ("concurrent edits are rare") is weak and invites skepticism. The real argument ("money fields are source data or planning data, never derived totals") is much stronger.

**Recommended action**: Rewrite the justification. The architecture decision is correct, but the reasoning should stand on the data model, not on probability. Also: Finding 1 (stale-read overwrite) still applies to these fields and is the real risk.

---

## Finding 4: Archiving Is a Hidden Multi-Doc Operation (MEDIUM)

**What the doc says**: Soft deletes (setting `isArchived: true`) are Tier 1 (single-doc fire-and-forget).

**What the codebase reveals**: `onSpaceArchived` trigger batch-updates ALL items with that `spaceId`, clearing `spaceId: null`. This is a fan-out write touching potentially dozens of documents. If the trigger fails (deployment issue, timeout on large batch), items retain references to an archived space — they'll display a space name that no longer exists in the UI, or worse, get filtered out of views that exclude archived spaces.

The doc classifies archiving as Tier 1 but acknowledges the Tier 4 cleanup trigger. The gap: there's no monitoring or user visibility if the trigger fails. The batch operation (500 ops/batch) has no retry mechanism — errors are logged and swallowed.

**How likely**: Low frequency (spaces aren't archived often), but high impact when it fails — items become orphaned in a ghost space.

**Recommended action**: Accept the risk but add a defensive read: when displaying an item's space, handle the case where `spaceId` references an archived/deleted space gracefully (show "No space" instead of crashing or showing stale data). This is cheaper than promoting archiving to Tier 2. Also consider: should the client clear `spaceId` on affected items it knows about (from its local cache) at archive time, as a best-effort supplement to the trigger?

---

## Finding 5: No Media Upload Retry or Orphan Cleanup (MEDIUM)

**What the doc says**: Photos/receipts are a core workflow. Storage is scoped by tenant/project path.

**What the codebase reveals**:
- `processUploadQueue()` exists but only runs on **manual triggers** (user taps Retry, or project screen creation). No background retry.
- Failed uploads are stored in AsyncStorage indefinitely. Items/transactions reference `offline://<mediaId>` URLs that never resolve to remote storage.
- `cleanupOrphanedMedia()` **exists but is never called** — dead code. No garbage collection.
- Local media files accumulate in the FileSystem cache directory with no eviction policy.

Concrete scenario: Designer takes 20 photos on-site with no connectivity. Navigates away. Upload queue has 20 pending jobs. If the app is killed and reopened, uploads only resume if the user happens to trigger `processUploadQueue()`. Photos referenced in items show broken/placeholder images for other team members indefinitely.

**How likely**: High. This is the primary use case — photos taken on job sites with poor connectivity.

**Recommended action**:
1. Run `processUploadQueue()` on app foreground (AppState → active), not just on manual triggers.
2. Wire up `cleanupOrphanedMedia()` on a periodic schedule or app startup.
3. Add a bounded cache policy for local media (e.g., LRU eviction after 500MB).

---

## Finding 6: Listener Reattach Failures Are Silent (MEDIUM)

**What the doc says**: `ScopedListenerManager` detaches listeners on background, reattaches on foreground.

**What the codebase reveals**: If a listener factory throws during reattach, the error is logged but the scope is still marked `isAttached: true`. The user sees stale cached data with no indication that real-time updates have stopped. Only a manual refresh (`refreshAllScopes()`) recovers.

Concrete scenario: App goes to background. User's auth token expires (Firebase tokens last 1 hour). App comes to foreground. Listener reattach fails because the token is expired and refresh hasn't completed yet. Scope is marked attached. User sees stale data. Firebase eventually refreshes the token, but listeners are never re-created because the scope thinks it's already attached.

**How likely**: Medium. One-hour token expiry + background/foreground transitions is a realistic combination, especially for designers who switch between apps frequently on-site.

**Recommended action**: If any listener in a scope fails to reattach, mark the scope as `isAttached: false` and schedule a retry (e.g., exponential backoff, max 3 attempts). Surface a subtle indicator if all retries fail.

---

## Finding 7: Request-Doc Failure Has No Recovery Path (LOW-MEDIUM)

**What the doc says**: Request-docs use `opId` for deduplication. Cloud Functions set status to `applied` or `failed`.

**What the codebase reveals**: When a request-doc Cloud Function fails, it sets `status: 'failed'` with an `errorCode` and `errorMessage`. But:
- There is no client-side UI that monitors request-doc status and surfaces failures to the user.
- There is no automatic retry. The `opId` dedup would allow safe retry, but nothing triggers it.
- There is no dead-letter queue or admin dashboard for stuck requests.

Concrete scenario: Designer moves an item from Project A to Business Inventory. The request-doc is created offline. When connectivity returns, the Cloud Function runs but fails (e.g., item was already moved by another user). The request-doc gets `status: 'failed'`. The client UI shows the item in its pre-move state (since the optimistic local write didn't happen — request-docs don't touch local cache). The user doesn't know the move failed unless they notice the item is still in Project A.

**How likely**: Low — the precondition checks in request handlers are thorough. But "low probability, high confusion" when it does happen.

**Recommended action**: Add a lightweight request-doc status listener on screens that initiate moves. Show a toast/banner if any recent request for the current project has `status: 'failed'`. This is a small addition with high UX value.

---

## Finding 8: `userHasEdited` Pattern Missing from Most Edit Screens (LOW)

**What the doc says**: Reliability Rule 2 prescribes the `userHasEdited` ref pattern for edit screens.

**What the codebase reveals**: Only Project Edit implements `userHasEditedBudgets`. Item Edit, Transaction Edit, and Budget Category Edit don't use it at all.

**What could go wrong**: Without this guard, if a subscription fires while the user is mid-edit (e.g., another user edits the same doc, or the cache-first double-callback delivers a second payload), the form state gets overwritten. The user's in-progress edits vanish.

**How likely**: Low — the cache-first prelude fires quickly, and true concurrent edits are rare. But the double-callback pattern means there are always at least 2 subscription callbacks. If the user starts typing between callback 1 (cache) and callback 2 (server), their edits get clobbered.

**Recommended action**: Apply the `userHasEdited` pattern consistently to all edit screens. It's a 5-line addition per screen.

---

## Finding 9: No Schema Evolution Strategy (LOW)

**What the doc says**: Nothing. Schema evolution is not mentioned.

**What the codebase reveals**: Ad-hoc read-time normalization (e.g., `itemsService.ts` handles legacy `description` field). No version numbers, no migration framework, no "run once" migrations.

**How likely to cause problems**: Low in the near term — the app is early-stage and the schema is still stabilizing. Medium in 12+ months as the schema accumulates more legacy shapes.

**Recommended action**: Accept for MVP. When the schema stabilizes, add a `schemaVersion` field to documents and a read-time normalizer that upgrades old shapes. This is a pattern, not infrastructure — no migration framework needed.

---

## Finding 10: The "Do NOT Build" List Is Sound (Observation)

- **No custom sync engine**: Correct. Firestore's native SDK handles this well.
- **No client-side conflict resolution**: Correct given the data model (Finding 3).
- **No request-docs for single-doc edits**: Correct. Would break offline-first.
- **No compare-before-commit UX**: Partially wrong — a lightweight staleness check (Finding 1, mitigation 2) is not the same as a full compare-before-commit UI. The doc conflates the two.
- **No fine-grained per-field permissions**: Correct for MVP. The real risk is stale overwrites (Finding 1), not unauthorized writes.

---

## Overall Assessment

**The architecture is sound for the stated use case.** The four-tier write classification, offline-first principles, and decision to avoid request-docs for single-doc edits are all correct. The data model's separation of source data (prices, planned budgets) from derived data (budget progress) is clean and makes last-write-wins safe for money fields.

**Two structural issues need attention before they cause real user pain:**

1. **Stale-read full-form overwrite (Finding 1)** is the most likely source of real data loss. It's not a concurrent-edit problem — it's a "designer got interrupted and saved 30 minutes later" problem. The fix (partial writes or staleness detection) is straightforward.

2. **Media upload reliability (Finding 5)** directly threatens the core use case. Designers taking photos on job sites with no connectivity is the primary scenario, and the current upload pipeline requires manual intervention to retry. Automatic retry on app foreground is essential.

Everything else is accept-the-risk-for-MVP territory. The phantom writes issue (Finding 2) is theoretically concerning but practically unlikely. The request-doc failure visibility (Finding 7) and listener reattach (Finding 6) are worth addressing but won't cause widespread pain at 2–5 user scale.

The document's weakest section is its justification for last-write-wins on money fields. The argument "concurrent edits are rare" is the wrong argument. The right argument is "these fields are source/planning data, not derived totals" (Finding 3). Rewriting this section will make the architecture more defensible to future reviewers and prevent someone from second-guessing it and adding unnecessary complexity.
