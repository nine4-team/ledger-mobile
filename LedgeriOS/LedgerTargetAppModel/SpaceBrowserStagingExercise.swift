// DRAFT scaffold only: no executable Space-browser AppModel exists here.
//
// A later READY implementation may import Core contracts only and orchestrate
// one exact Project-or-Business-Inventory Space list plus one selected existing
// exact-Space core-details observation. It must render honest waiting, partial,
// stale, ready, authoritative-empty, and bounded-failure state; expose active
// Spaces in frozen deterministic order and navigate by represented stable
// SpaceID rather than display name or row position. Search is not part of the
// current frozen provider-free contract and cannot be invented here.
//
// Request replacement and cancellation must generation-fence both list and
// detail events. The model must not import implementation-specific storage,
// transport, security, source-backend, mutation, or production-routing APIs.
// It must omit unavailable Item counts rather than substitute zero and must not
// invent an archived-list section.
