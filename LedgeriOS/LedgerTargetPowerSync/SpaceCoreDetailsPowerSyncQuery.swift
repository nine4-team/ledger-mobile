// READY scaffold — no executable provider exists at this checkpoint.
//
// Frozen implementation boundary:
// - implement only SpaceCoreDetailsQuerying for one exact AccountID/SpaceID;
// - reconstruct the verified SpaceCoreDetailsSnapshot without changing Core;
// - combine exact-Space rows and current-process stream completion causally;
// - include active and archived Spaces, ordered checklist hierarchy, and no Items/media;
// - fail closed on malformed, foreign, duplicate, incomplete, or revoked evidence; and
// - cancel, unsubscribe, and drain every owned observer before database close.
