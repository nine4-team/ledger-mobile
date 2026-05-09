# Vendor Filtering Improvements

Triggered by an MCP session trying to find all "thrift store" items in a project. The current toolkit forces the agent to enumerate vendor names by hand because there's no notion of vendor *class*. This plan covers the cheap MCP fixes plus a sketch for the real fix (vendor classification) so we can decide whether to build it.

## Scope

Two phases. Phase 1 ships immediately. Phase 2 is a proposal — do not start without product sign-off.

---

## Phase 1 — MCP filter polish (low effort, ship now)

### 1.1 Add `source` filter to `list_items`

**Why.** `bulk_update_items` already filters items by `source` ([mcp-server/src/tools/items.ts:634](../../mcp-server/src/tools/items.ts:634)), but `list_items` ([items.ts:171-224](../../mcp-server/src/tools/items.ts:171)) does not. Inconsistent and forces callers to fetch-and-filter.

**Change.** Add `source: z.string().optional()` to the `list_items` zod schema and `query.where("source", "==", source)` in the handler. Mirror the existing pattern from `bulk_update_items`.

**Files.** `mcp-server/src/tools/items.ts` only.

**Test.** Add a vitest case to `mcp-server/test/` that calls `list_items({ projectId, source: "Goodwill" })` and asserts only matching items return.

### 1.2 Add `sources: string[]` (multi-value) to `list_transactions` and `list_items`

**Why.** Today an agent has to make N calls to enumerate a small set of known thrift names. Firestore `in` queries take up to 30 values — fine for this use case.

**Change.** Add `sources: z.array(z.string()).max(30).optional()` alongside the existing `source` field. If `sources` is set, use `query.where("source", "in", sources)`. Reject when both `source` and `sources` are passed.

**Files.** `mcp-server/src/tools/transactions.ts`, `mcp-server/src/tools/items.ts`.

**Caveats to call out in the tool description.**
- `in` queries can't be combined with another inequality filter on a different field (Firestore restriction). Document this.
- Cap at 30 values — surface a validation error above that.

**Test.** Vitest case: `list_transactions({ sources: ["Goodwill", "Savers"] })` returns only matches.

### 1.3 Update tool descriptions to surface what already works

The other agent didn't realize `search_items` / `search_transactions` already do case-insensitive substring search across `source`. Tighten the descriptions of both `list_*` and `search_*` so an agent picks the right one without reading the impl. One sentence each:

- `list_*`: "Exact-match filters. For substring/keyword search across source/notes/name, use `search_*`."
- `search_*`: "Substring search across source/notes/name/sku. Use this when you don't know the exact vendor string."

**Files.** `mcp-server/src/tools/items.ts`, `mcp-server/src/tools/transactions.ts`.

### 1.4 Acceptance

- `list_items` accepts and applies `source` (exact) and `sources` (in).
- `list_transactions` accepts and applies `sources` (in).
- New vitest cases pass.
- Tool descriptions cross-reference each other.
- No client changes — MCP-only.

---

## Phase 2 — Vendor classification (proposal, needs sign-off)

This is the real fix for "find all thrift-store items." Don't build it without confirming with the user that the value justifies the migration.

### Problem

`source` is free text. "Goodwill," "Goodwill Industries," "GW St George," "DI," "Deseret Industries," "Savers" all denote thrift but share no key. An agent (or human report) can't reliably ask "everything from a thrift store" — it has to enumerate names. Same problem will hit any future query that wants a vendor *class*: marketplace (eBay, Facebook Marketplace, Craigslist), big-box retail, designer wholesale, estate sale, etc.

### Proposed design

Promote `VendorDefaults` from a flat `[String]` ([Models/VendorDefaults.swift](../../LedgeriOS/LedgeriOS/Models/VendorDefaults.swift)) to a per-account `vendors` subcollection of records:

```
accounts/{accountId}/vendors/{vendorId}
  name: string            // canonical display name, e.g. "Goodwill"
  aliases: string[]        // free-text variants we've seen, e.g. ["Goodwill Industries", "GW St George"]
  type: VendorType         // enum: retail | thrift | marketplace | wholesale | estate-sale | service | other
  notes: string?
```

Transactions and items continue to store `source` as a string (don't break existing data). A Cloud Function (or write-path resolver) attaches a denormalized `vendorId` and `vendorType` to new transactions when `source` matches a known name or alias. Backfill once for existing data.

### What this unlocks

- Filter `list_transactions` / `list_items` by `vendorType: "thrift"` (one call, no enumeration).
- Spending-by-vendor reports can group by canonical vendor instead of every spelling.
- Vendor-defaults UI becomes a real registry instead of a free-text list.

### What it costs

- New `Vendor` model, Firestore rules, repository, settings UI to manage records and types.
- Backfill script to migrate `VendorDefaults.vendors` → records and infer `type` (LLM-assisted classification with human review).
- Resolver on transaction write that attaches `vendorId`/`vendorType` from `source`. Ambiguity handling when the source string is unknown.
- MCP additions: `vendorType` filter on `list_*`, plus `list_vendors` / `set_vendor_type` for management.

### Open questions for the user

1. Is "find by vendor class" a recurring need, or was this a one-off cleanup task? If one-off, skip Phase 2 and use Phase 1 + `search_transactions` to enumerate names manually.
2. Who maintains the type assignments — the user, or do we let an LLM seed them and the user approve?
3. Estate-sale and antique-mall sit between thrift and retail. Are those distinct types or grouped under thrift?
4. Should `vendorType` propagate to items as a denormalized field for fast item-side filtering, or always be resolved via the linked transaction?

### Recommendation

Build Phase 1 now. Hold Phase 2 until there's a second use case beyond the Sandra Bahama cleanup that wants vendor *class*. One real problem doesn't justify a registry; two does.
