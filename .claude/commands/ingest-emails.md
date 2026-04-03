---
name: ingest-emails
description: Scan Gmail for order confirmation emails, parse them, match to Ledger projects, and create transactions via MCP. Deduplicates by email ID.
user-invocable: true
disable-model-invocation: false
argument-hint: [after:2026/3/1 from:vendor@example.com]
---

# Email Ingestion Skill

Scan a Gmail inbox for order confirmation emails, parse each one, match it to a Ledger project, and create a transaction via the Ledger MCP server.

## User Input

```
$ARGUMENTS
```

If `$ARGUMENTS` is empty, default to searching for order confirmations from the last 7 days.
If `$ARGUMENTS` contains a Gmail search query (e.g. `after:2026/3/1 from:restorationhardware.com`), use it directly.

---

## Workflow

### Step 1: Load Projects

Call `list_projects` (filter: "active") to get all active projects. Cache the result — you'll need each project's `name`, `clientName`, `notes`, and `id` for matching.

**Project notes are critical.** They may contain:
- Payment card last 4 digits (e.g. "Amex ...1234")
- Shipping addresses
- Client names or aliases
- Vendor accounts or order number prefixes

### Step 2: Search Gmail

Call `gmail_search_messages` with a query. Build the query as follows:

**Default query** (no user input):
Use a multi-pass vendor-based search. Subject-line searches are unreliable — order emails use inconsistent subjects ("Success!", "has shipped!", "Thank you for your order", etc.). Instead, search by known vendor senders and Gmail category:

**Pass 1 — Known vendors (high signal):**
Run one search per vendor cluster. Combine related senders with OR:
```
newer_than:7d (from:amazon.com OR from:wayfair.com OR from:ruggable.com OR from:potterybarn.com OR from:crateandbarrel.com OR from:restorationhardware.com OR from:westelm.com OR from:perigold.com OR from:serenaandlily.com OR from:anthropologie.com OR from:target.com OR from:overstock.com OR from:etsy.com OR from:homedepot.com OR from:lowes.com OR from:bernhardt.com OR from:arhaus.com OR from:ballarddesigns.com OR from:luluandgeorgia.com OR from:mcgeeandco.com OR from:worldmarket.com)
```

**Pass 2 — Catch-all for unknown vendors:**
```
newer_than:7d category:updates -category:promotions (order OR shipped OR tracking OR receipt OR invoice OR confirmation)
```

This catches order emails from vendors not in the known list. The `category:updates` filter excludes marketing/promotional emails while keeping transactional ones.

**Triage pass results:** From both passes, deduplicate by messageId, then filter out non-order emails (newsletters, promos, social notifications, account alerts). Only process emails that contain order/shipping/receipt content — look for signals like order numbers, dollar amounts, shipping addresses, line item tables.

**User-provided query:** Use `$ARGUMENTS` as-is. Do not append extra filters — trust the user's query.

Set `maxResults: 50` per search. Paginate if `nextPageToken` is returned.

### Step 3: Process Each Email

For each email returned by the search:

#### 3a. Read the Full Email

Call `gmail_read_message` with the `messageId`.

#### 3b. Parse Order Details

Extract from the email body and headers:

| Field | Where to find it |
|-------|-----------------|
| **Vendor/Source** | From address domain, or store name in email body |
| **Order number** | Look for "Order #", "Order Number:", "Confirmation #" patterns |
| **Order date** | Email date header, or date mentioned in body |
| **Total amount** | "Order Total", "Total", "Amount Charged" — convert to cents |
| **Subtotal** | Pre-tax amount if listed separately |
| **Tax** | Tax amount or rate if listed |
| **Payment method** | "Payment Method", "Paid with", card type + last 4 |
| **Shipping address** | Delivery address if present |
| **Line items** | Individual items with names, quantities, prices |
| **Receipt/Invoice URL** | "View invoice", "Print receipt", "Order summary" links — any URL that leads to a printable receipt or invoice page |
| **Tracking URL** | "Track your package", "Track shipment", "View order status" links |
| **Order status URL** | "View order", "Order details", "Manage order" links |
| **Email ID** | The Gmail `messageId` — used for deduplication |
| **Email subject** | The subject line |

If you can't parse a required field, still create the transaction — mark it `needs_review` so the user can fill in the gaps.

#### 3c. Check for Duplicates

Call `search_transactions` with the vendor name as the query. Scan results for an existing transaction where:
- `ingestionMeta.emailId` matches this email's `messageId`, OR
- Same `source` + same `amountCents` + same `transactionDate` (within 1 day)

If a duplicate is found, **skip this email** and log it. Move to the next email.

#### 3d. Match to Project

Compare the parsed email against each project. Score each project on these signals:

| Signal | Weight | How to match |
|--------|--------|-------------|
| **Payment card last 4** | Highest | Email's payment method last 4 digits matches digits in `project.notes` |
| **Shipping address in notes** | High | Email's shipping address matches address fragments in `project.notes` |
| **Client name** | High | Email's shipping/billing name matches `project.clientName` (exact or close) |
| **Shipping address cross-ref** | Medium | Email's shipping address matches an address seen in another email already matched to a project in this session, or matches address details in existing transaction notes for a project |
| **Vendor history** | Medium | Project already has transactions from same vendor/source (call `list_transactions` with `source` filter) |
| **Order number prefix** | Low | Order number pattern matches a prefix mentioned in `project.notes` |

**Address cross-referencing:** As you process emails, build an address-to-project map from shipping addresses you extract. When a new email ships to an address you've already matched to a project (even via a different client/team member name), use that as a medium-confidence signal. This handles the common case where a team member (e.g. "Lisa Fisher") orders items shipped to a client's project address (e.g. "2773 E Cliff Shadow Dr" = Witzenman's 2nd Home).

Also check existing transaction notes — they sometimes contain shipping addresses that can confirm a project match.

**Confidence scoring:**
- **High confidence** (auto_matched): Client name matches `project.clientName`, OR payment card last 4 matches, OR 2+ medium signals align
- **Medium confidence** (needs_review): Address cross-reference match but name doesn't match client, OR single strong signal
- **Low confidence** (needs_review): Only vendor history, or no matches at all
- **No match**: No signals match any project — create transaction without `projectId`, set `ingestionStatus: "needs_review"`

#### 3e. Detect Split Shipments

If multiple emails share the same order number but have different shipment contents or dates, they're split shipments. Track the order numbers you've seen. When you encounter a second email for the same order number:
- Set `ingestionMeta.linkedIngestionIds` on both transactions to reference each other
- Use the same `projectId` match as the first shipment

#### 3f. Create Transaction

Call `create_transaction` with:

```
projectId: <matched project ID, or omit if no match>
budgetCategoryId: <from project's budget categories if determinable, otherwise use a sensible default or omit>
source: <vendor name>
amountCents: <total in cents>
subtotalCents: <pre-tax amount if parsed>
taxRatePct: <tax rate if parsed>
transactionDate: <order date as "YYYY-MM-DD">
paymentMethod: <e.g. "Visa ...1234">
notes: <line items summary, order number, shipping address, then links section — see format below>
receiptEmailed: true
ingestionSource: "email"
ingestionStatus: <"auto_matched" if high confidence, "needs_review" if low>
ingestionMeta: {
  emailId: <Gmail messageId>,
  subject: <email subject>,
  inbox: <email address that received this>,
  matchConfidence: <0.0 to 1.0>,
  matchReason: <brief explanation, e.g. "card last 4 match: ...1234">,
  orderNumber: <order number if parsed>,
  linkedIngestionIds: <array of related transaction IDs for split shipments>
}
```

**Notes format:** Structure the notes field like this:
```
<item description> — <quantity>. Order #<order number>. Shipped to <name>, <address>.

Invoice: <invoice/receipt URL>
Track: <tracking URL>
Order: <order status/details URL>
```
Only include link lines that were found in the email. These give the user one-tap access to the original receipt, tracking, and order pages.

**Required fields:** `amountCents` and `budgetCategoryId` are required by `create_transaction`. If you can't determine the budget category, check the project's categories via `get_project_budget_categories` and use the most common one (often "Furnishings"). If still unclear, note this in the transaction's `notes` field and set `ingestionStatus: "needs_review"`.

### Step 4: Report Results

After processing all emails, output a summary:

```
## Email Ingestion Summary

Emails scanned: X
Transactions created: Y
  - Auto-matched (high confidence): A
  - Needs review (low confidence): B
Duplicates skipped: Z
Errors: W

### Created Transactions
- [Vendor] $Amount → Project Name (auto_matched / needs_review)
- [Vendor] $Amount → No project match (needs_review)
...

### Skipped (duplicates)
- [Vendor] $Amount — already exists as transaction [ID]
...
```

---

## Budget Category Selection

When a project match is found, try to assign the right budget category:

1. Call `get_project_budget_categories` for the matched project
2. If the vendor or line items suggest a category (e.g. "furniture" → Furnishings, "paint" → Materials), use it
3. If unclear, use the project's most-used category (check existing transactions for that vendor via `list_transactions`)
4. If still unclear, pick "Furnishings" as default (most common for this business) and flag for review

---

## Error Handling

- If Gmail search returns no results: report "No new order confirmations found" and exit
- If email parsing fails for a specific email: log the error, skip that email, continue with others
- If `create_transaction` fails: log the error with email subject and vendor, continue with others
- If `list_projects` fails: abort — can't match without projects

---

## Important Notes

- **Never modify or delete emails.** This skill is read-only for Gmail.
- **Amounts are in cents.** $150.00 = 15000 cents. Be precise with parsing.
- **Tax handling:** If the email shows tax separately, set `subtotalCents` (pre-tax) and `taxRatePct`. Set `amountCents` to the total including tax.
- **One transaction per order.** Don't create separate transactions for each line item — line items become Items later (manually or via a future skill).
- **Deduplication is critical.** Always check before creating. The `ingestionMeta.emailId` is the primary dedup key.
