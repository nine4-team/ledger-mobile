// DRAFT scaffold only — no network behavior exists at this checkpoint.
//
// The implementation will post client-rename-v1 canonical JSON as text using
// only an injected scoped-user access token and publishable key. It will never
// materialize ExpectedClientRevision through Double/JavaScript-style numeric
// coercion, and it will validate exact Operation, Account, Client, fingerprint,
// terminal state and stable result code before queue completion. No service-role
// credential, hosted endpoint or Firebase adapter belongs in this leaf. O-043
// must first define the exact shared Client display-name input boundary.
