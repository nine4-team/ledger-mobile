# Ledger

Ledger is a project, purchasing, inventory, budget, and billing system built for
an interior-design business. It replaces disconnected spreadsheets and manual
handoffs with one operational record from sourcing through client invoicing.

[View the product site](https://ledger.nine4.co/)

## What the product handles

- projects, spaces, budgets, and account-specific budget categories
- purchases, returns, business inventory, and project-to-project item movement
- receipt and invoice import with item extraction and review workflows
- item images, quick drafts, search, filters, and bulk operations
- client invoices, transaction exports, and project reports
- role-based access to financial and operational data
- iOS, iPadOS, and macOS distribution, including TestFlight and Sparkle releases

## Architecture

The primary client is a native SwiftUI application in `LedgeriOS/`. Firebase Auth,
Firestore, Storage, Cloud Functions, and security rules provide the shared backend.
The codebase keeps accounting and inventory invariants in testable calculation and
policy layers rather than embedding them only in views.

`mcp-server/` contains a TypeScript MCP service that exposes the same business data
through authenticated, schema-defined tools. That makes it possible to add AI
workflows without bypassing the application's permissions or domain rules.

```text
SwiftUI app ─┐
             ├─ authenticated domain operations ─ Firebase
MCP service ─┘
```

## Repository guide

- `LedgeriOS/` — native client, models, state, reusable components, and tests
- `firebase/` — Firestore and Storage rules, indexes, and backend support
- `mcp-server/` — authenticated MCP tools for projects, transactions, items, and reporting
- `user-docs/` — task-oriented documentation for the people who use Ledger
- `scripts/` and `fastlane/` — validation and release automation

## Validation

The native test target covers calculation, validation, routing, access-policy, and
domain-invariant behavior. The MCP package has its own TypeScript build and focused
tests. Release scripts package the macOS app and drive TestFlight distribution.

Local execution requires project-specific Firebase configuration and Apple signing,
so this repository is best reviewed as the implementation behind the linked product
rather than as a one-command sample app.

## Privacy

No production service-account credentials are stored in the repository. Firebase
client configuration identifies the app project but does not grant administrative
access; authorization is enforced by authentication, security rules, and trusted
server operations.
