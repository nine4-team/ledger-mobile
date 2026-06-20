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

### With Firebase Emulators (Development)

Start the emulators first:

```bash
npm run dev:native
```

The `.mcp.json` config already points at the local emulators. Restart Claude Code after building.

### With Production Firestore

Update `.mcp.json` env vars:

```json
{
  "mcpServers": {
    "ledger": {
      "command": "node",
      "args": ["mcp-server/build/index.js"],
      "env": {
        "FIREBASE_PROJECT_ID": "ledger-nine4",
        "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/service-account.json",
        "LEDGER_ACCOUNT_ID": "your-account-id"
      }
    }
  }
}
```

Remove `FIRESTORE_EMULATOR_HOST` to connect to production.

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
- `create_item`, `update_item`, `delete_item`
- `create_space`, `update_space`
- `update_project_budget_allocation`, `enable_category_for_project`

### Inventory Operations
- `sell_items_from_inventory_to_project` — Sell items from business inventory into a project. Creates ONE new immutable Purchase transaction per call (auto-ID, frozen shape). Cap: 100 items. One budget category per batch.
- `sell_items_from_project_to_inventory` — Sell project-originated items into business inventory (the business is acquiring them). Creates ONE new immutable Sale transaction against the source project. Items must have originated in that project; items that previously passed through inventory must use `return_items` instead.
- `sell_items_from_project_to_project` — Sell items from one project directly to another in a single atomic batch (origin-aware first hop into inventory + Purchase into destination). Cap: 100 items. One destination category per batch.
- `return_items` — Return items to a vendor (attach to an existing Return transaction) or back to business inventory (new or reused Return transaction with `source: "Business Inventory"`; wipes item category). Cap: 100 items.

Sale transaction shape fields (`amountCents`, `itemIds`, `budgetCategoryId`, `type`, `source`, `projectId`) are frozen after creation — enforced by Firestore rules and server-side validation. Item invariant: `(projectId == null) ↔ (budgetCategoryId == null)`.

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
