// READY scaffold only — the executable provider test suite is absent.
//
// Planned tests use one real encrypted isolated local database and cover both
// Project and Business Inventory scope: active same-scope rows, duplicate-name
// deterministic order, exact revisions, explicit incomplete/partial/stale/
// ready/authoritative-empty/failure states, exact Project/Inventory Sync Stream
// subscription identity, first-sync completeness, restart with completeness
// reset, reactive row/completeness arrival in both orders, membership loss/recovery,
// cross-Account/cross-scope/inactive/malformed refusal, content-bound versions,
// stable query identity, unsubscribe, consumer cancellation and provider/runtime
// drainage.
//
// Tests must not insert through a product writer, exercise Space or Item
// mutation, claim hosted authorization, inspect production data, or reinterpret
// the verified provider-free evidence record.
