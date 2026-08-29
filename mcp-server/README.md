# Ledger MCP Server

MCP server that connects Claude Code to your Ledger app data via Firestore.

## Setup

```bash
cd mcp-server
npm install
npm run build
```

The MCP config is in `.mcp.json` at the repo root. Claude Code will prompt you to approve the server on next launch.

## Usage

### Local MCP Against Real Firestore

Use the real Firebase project for local MCP work. The repo's `.mcp.json` should point at the built server and a Firebase Admin service-account key. Do **not** set `FIRESTORE_EMULATOR_HOST` for normal MCP development or validation.

Example `.mcp.json`:

```json
{
  "mcpServers": {
    "ledger": {
      "command": "node",
      "args": [
        "mcp-server/build/index.js",
        "--credentials",
        "/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json"
      ],
      "env": {
        "FIREBASE_PROJECT_ID": "ledger-nine4",
        "LEDGER_ACCOUNT_ID": "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94"
      }
    }
  }
}
```

Alternative: omit `--credentials` and set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json` in `env`.

If you see `invalid_grant`, `invalid_rapt`, or other ADC reauth errors, use the service-account key path above instead of Application Default Credentials.

### Validation

For MCP changes, the minimum local checks are:

```bash
cd mcp-server
npm run build
git diff --check
```

For write-path changes, run a disposable smoke against real Firestore using a service account, then clean up the created documents. Prefer a tiny create/read/update/promote/delete flow over the old emulator harness, because the app and remote MCP server operate against real Firestore.

### Legacy Emulator Harness

`npm test` currently uses an older Firestore emulator-based Vitest harness under `mcp-server/test/`. Treat it as legacy coverage for specific inventory movement tests, not as the default way to validate MCP behavior. Do not start or debug emulators just to verify ordinary MCP changes unless you are intentionally working on that test harness.

## Available Tools

### Read/Query
- `list_projects` — List projects (active, archived, or all)
- `get_project` — Single project with budget summary
- `get_project_budget` — Live budget breakdown computed from transactions
- `list_transactions` — Transactions with filters (project, category, type)
- `get_transaction` — Transaction with linked items resolved
- `search_transactions` — Search by vendor/notes
- `list_items` — Items with filters (project, space, status, bookmark)
- `get_item` — Single item details
- `search_items` — Search by name/SKU/source
- `list_spaces` — Spaces with item counts
- `get_space` — Space with items and checklist progress
- `list_budget_categories` — Account-level categories
- `get_project_budget_categories` — Project categories with spend

### Write
- `create_project`, `update_project`, `archive_project`
- `create_transaction`, `update_transaction`, `cancel_transaction`
  - Note: `create_transaction` rejects `type: "Sale"` — use `sell_items_from_project_to_inventory` instead
  - `update_transaction` accepts `projectId: null` to correct an ordinary transaction into business inventory; it clears `budgetCategoryId` and does not move linked items or create an inventory movement
- `create_item`, `update_item`, `delete_item`
- `attach_item_image({ itemId, fileData|fileUrl, fileName, contentType?, isPrimary?, position? })` — upload an item-owned attachment; the first image becomes primary
- `set_primary_item_image({ itemId, imageUrl })` — atomically choose the primary and move it to index 0; never touches Storage
- `reorder_item_images({ itemId, orderedImageUrls, primaryImageUrl? })` — atomically reorder the exact current image set while preserving metadata; never touches Storage
- `detach_item_image({ itemId, imageUrl })` — remove only the Firestore attachment reference; never touches Storage
- `delete_item_image({ itemId, imageUrl })` — **destructive** for item-owned objects only; external, shared, `protoItems`, and other-item objects are detached but preserved
- `promote_quick_draft_item({ quickDraftItemId, ..., primaryImageUrl?, mergeIntoItemId? })` — copy and verify draft originals/thumbnails into the destination item's namespace before atomically creating/merging; draft originals are preserved
- `create_space`, `update_space`
- `update_project_budget_allocation`, `enable_category_for_project`

### Inventory Operations
- `return_items_from_inventory_to_project` — Reverse an active Sale-to-Inventory acquisition, returning project-originated items to that project/category at the exact frozen accounting values. The caller cannot choose destination accounting fields. Different original categories create separate Purchases atomically; ambiguous legacy records fail safely. Items that came home through Return are ordinary sellable inventory and do not use this tool.
- `sell_items_from_inventory_to_project` — Sell items from business inventory into a project. Creates ONE new Purchase transaction per call (auto-ID). Its amount/subtotal follow later project-price changes until the item is on a paid invoice; the remaining accounting identity is frozen. Cap: 100 items. One budget category per batch.
- `sell_items_from_project_to_inventory` — Sell project-originated items into business inventory (the business is acquiring them). Creates ONE new Sale transaction against the source project. Items must have originated in that project; items that previously passed through inventory must use `return_items` instead.
- `sell_items_from_project_to_project` — Sell items from one project directly to another in a single atomic batch (origin-aware first hop into inventory + Purchase into destination). Cap: 100 items. One destination category per batch.
- `return_items` — Return items to a vendor (attach to an existing Return transaction) or back to business inventory (always creates a new per-batch Return transaction with the inventory source label; wipes item category). Cap: 100 items.

Inventory movement identity fields (`budgetCategoryId`, `type`, `source`, `projectId`) are frozen after creation, and clients cannot edit movement totals directly. Inventory-entry items also preserve the movement transaction, source project/category, and per-item subtotal/amount. Return to Project consumes that snapshot only when the current movement is an active Sale-to-Inventory acquisition; the generic inventory-sale tool refuses those candidates. A current Return means the item came home and is ordinary sellable inventory. The trusted item-price trigger adjusts `amountCents`/`subtotalCents` only for a project-side Purchase from Inventory when its sold item's effective project price changes. Other movement totals remain frozen. `itemIds` tracks active membership. Item invariant: `(projectId == null) ↔ (budgetCategoryId == null)`.

### Item Copies and Quantity Expansion

When a receipt line, quick draft, or source item is expanded into multiple physical item documents, every document keeps the source `name` exactly, byte-for-byte. Repeated identical names are valid because document IDs identify the physical records. Reconstruction and duplication workflows must not append unit counts, “copy,” “duplicate,” parenthetical numbers, or any other generated differentiator. Names differ only when the user explicitly requests distinct names or source evidence names individual units differently. Inventory movements preserve names and this release does not rename existing data.

### Analytics
- `project_health` — Budget utilization, item counts, attention items
- `inventory_summary` — Business inventory overview
- `spending_by_vendor` — Spending by vendor/source
- `budget_variance_report` — Per-category over/under budget
- `items_needing_attention` — Items with data quality issues

### Lineage
- `get_item_history` — Item movement history
- `get_project_movements` — Items moved into/out of a project

## HTTP Mode (for Claude Co-work)

The server also runs as an HTTP endpoint for use with Claude Co-work or any remote MCP client. Requests are authenticated via Firebase ID tokens.

### Run locally

```bash
PORT=8080 FIREBASE_PROJECT_ID=ledger-nine4 npm run start:http
```

### Deploy to Cloud Run

```bash
# Build
npm run build

# Deploy
gcloud run deploy ledger-mcp \
  --source . \
  --region us-central1 \
  --project ledger-nine4 \
  --allow-unauthenticated \
  --update-env-vars FIREBASE_PROJECT_ID=ledger-nine4
```

**IMPORTANT:** Always use `--update-env-vars` (not `--set-env-vars`). `--set-env-vars` replaces ALL env vars, which would wipe `OAUTH_TOKEN_SECRET` and invalidate all existing OAuth tokens.

Cloud Run uses Application Default Credentials automatically — no service account key needed.

### Connect from Claude Co-work

Add the MCP server URL in Co-work's settings:
- **URL:** `https://ledger-mcp-XXXX-uc.a.run.app/mcp`
- **Auth:** Bearer token (Firebase ID token)

### Endpoints

| Path | Method | Auth | Description |
|------|--------|------|-------------|
| `/health` | GET | None | Health check |
| `/mcp` | POST | Bearer token | MCP protocol endpoint |

## Development

Watch mode for TypeScript changes:

```bash
npm run dev
```

Rebuild after changes:

```bash
npm run build
```
