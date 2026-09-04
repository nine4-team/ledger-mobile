// READY scaffold only — no executable behavior.
//
// This leaf will own the physical namespace derived from one already validated
// target environment plus one canonical PrincipalID/AccountID pair. The
// implementation must use the environment's LocalDataNamespace and persistence
// binding, validate every filesystem/Keychain component before side effects,
// map the scope to an opaque contained directory, and keep database/key/queue
// state distinct across bundle, environment, persistence-relevant manifest,
// Principal and Account. A changed persistence binding selects a different
// namespace; this leaf does not accept a caller-authored binding or claim to
// compare against separately stored binding metadata.
// It must not open a network connection, choose an Auth provider, activate a
// workspace, delete local data, or expose raw identifiers in filesystem paths.
