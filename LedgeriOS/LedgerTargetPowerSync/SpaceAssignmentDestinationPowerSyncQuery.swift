// READY scaffold only — no executable Space destination provider exists here.
//
// The implementation may add one module-internal PowerSync adapter for the
// verified SpaceAssignmentDestinationQuerying port. It observes only already-
// materialized active Space rows in the runtime's exact Account and exact
// Project-or-Business-Inventory ItemPlacementScope. It maps stable SpaceID,
// canonical SpaceDisplayName and exact UInt64 revision without authorizing,
// creating, editing, archiving, assigning or clearing anything.
//
// The provider starts incomplete and owns the exact current-process Sync Stream
// subscription that can establish query completeness: Project scope subscribes
// with the stable ProjectID; Business Inventory subscribes with the stable
// AccountID. It yields complete only after that exact subscription's first sync,
// canonicalizes through SpaceAssignmentDestinationDirectorySnapshot, retracts
// rows on membership loss, unsubscribes, and joins every owned observation before
// runtime close. Generic connection status, a cached row, an Account-wide array
// or route state can never manufacture completeness or eligibility.
// A-003 and A-004 remain proposed; this local adapter is not hosted Sync proof.
