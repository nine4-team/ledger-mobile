// READY scaffold only — executable provider work begins only after this exact
// synchronized READY checkpoint passes independent review and immutable CI.
//
// This module-internal provider will implement the existing backend-neutral
// BudgetCategoryReferenceQuerying port for one bound Account and Principal. It
// will observe only budget-category rows already materialized in that isolated
// encrypted Account workspace. A local active-membership row is a scope
// sentinel; it is not a fresh authorization claim.
//
// The query will not interpret visibility_class, financial_access, role, or an
// allowed-category list and will not filter or count hidden rows. Whatever
// subset trusted server/Sync authorization placed in the local database is the
// complete universe the adapter may inspect. visibleRowCountBeforeFiltering is
// therefore exactly the number of materialized rows emitted, never a hidden or
// server-side total.
//
// Account mismatch refuses before database observation. Missing active local
// membership yields no category rows and cannot become authoritative empty.
// Every material row must decode exact category/Account identity, name, kind,
// lifecycle, system/exclusion flags, UInt32 presentation order and UInt64
// revision; one malformed or duplicate row refuses the whole emission through
// a bounded local failure.
//
// Query-specific completeness is an independent current-process observation
// whose default is false. PowerSync hasSynced, lastSyncedAt, cached rows, or a
// prior process cannot manufacture complete-ready or authoritative-empty
// evidence. While completeness is false, rows are partial when no prior sync
// timestamp exists and stale when one exists. Only active local membership plus
// an explicit true completeness observation may produce ready evidence.
// Completeness and database changes are independently reactive, and consumer
// cancellation terminates both observations.
//
// LocalDataVersion and query fingerprint will be deterministic and content-
// bound to the Account, scope-sentinel state, completeness, quality, and every
// emitted category field in canonical presentation order. Restart begins with
// incomplete evidence until new current-process completeness arrives.
//
// Existing Postgres schema, RLS, Data API grants and illustrative PowerSync
// Sync configuration remain byte-unchanged and owned by the Project setup
// provider slice. O-026 remains open for category administration and final
// download visibility. This slice adds no category mutation, Project allocation
// mutation, form default, app/MCP entry point, hosted claim, Auth choice,
// source-backend adapter, migration, production access, release, or cutover
// behavior.
//
// The only permitted shared implementation touchpoints are frozen at this
// READY checkpoint by manifest identity and pre-implementation source hash:
// SWIFT-548A8A928FAE @ 20ccef5cbb04e905d113135b87b2bd22c38d75e0aa990021e7ba80faa4012b61,
// SWIFT-75CFE285AF37 @ 608d3d9319cbcc3082dc750e36545f00da43825702d4639b3311ee38038da987,
// TEST-8D6A15063B2D @ f70ed4ea57e30cbc8287b097644b56881b19627b8dd453be92cd85045df47137,
// and the two manifest aliases CONFIG-81235587F306 / FILE-A6E49E3815F4 for
// scripts/check-target-environment.mjs @
// af4ccc5b6401059f2d26326127a7d482b265cf5383ad18d2008bf542dff965bd.
// Their existing primary owners remain unchanged; no other executable path is
// admitted without returning this slice to review before implementation.
