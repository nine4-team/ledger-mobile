// Comment-only READY scaffold: no executable local OperationID integrity guard
// exists here. Implementation remains gated on this exact synchronized READY
// checkpoint passing immutable CI before this comment may be replaced.
//
// The guard will make `spike_local_operations.id` the single normal-path local
// ownership claim for an opaque, globally unique OperationID. It will not add a
// second registry table. Before any accepting provider replays or creates work,
// one shared inspection must run inside that provider's serialized
// writeTransaction and inventory every row that can claim the exact ID:
// local operation, synchronized result, the upload-queue (`ps_crud`) entry
// produced by each insert-only command view, any forbidden local-mutation queue
// entry for the synchronized operation-result table, pending Client/Project/
// allocation projections, archive overlays, and local-only Item assignment
// command evidence. Pinned PowerSync 0.5.3 does not persist a second backing row
// for an insertOnly write. The later clearing slice must register its own command
// table in this same inventory before it becomes executable.
//
// No evidence means the provider may continue toward an atomic claim. One
// typed same-family owner may continue only to the provider's state-aware exact
// replay validation. This includes a fully canonical applied or rejected
// creation row after its queue and reconciled/rejected pending projection have
// drained. Any still-present pending graph remains mandatory exact evidence;
// this guard adds no cleanup. The guard does not
// mistake every operation-only row for an orphan. A complete different-family
// owner or changed payload is a stable mismatch. Any untyped, nonterminal, or
// malformed operation-only row, other orphan, ambiguous pending row,
// contradictory family, duplicate-family graph, result-only graph, or otherwise
// incomplete evidence reserves the ID but never succeeds, repairs, deletes, or
// rebinds it.
// Equal fingerprints do not make distinct command families equivalent.
//
// Client and Project creation must begin writing their explicit command family
// and canonical envelope into the existing local-operation row. Pre-foundation
// rows may derive a family only from unambiguous surviving evidence; an
// unresolvable row remains reserved and fails closed. There is no shipped target
// database to migrate, and synthetic target databases remain disposable, but
// encrypted restart must preserve valid and malformed reservations exactly.
//
// Every current accepting store must invoke the same guard after the existing
// runtime/store Account/Principal scope boundary and before its first mutation.
// Client and Project creation remain scope-bound by their owning Account runtime;
// this slice does not invent constructor-bound scope in those database-only
// stores. Existing archive-family ID-prefix validation also remains before SQL;
// the two archive families have disjoint valid public ID shapes, while the guard
// still classifies synthetic/corrupt stored evidence from every family. The
// schema/source checker must compare the complete operation-bearing
// relation and provider inventory against this guard so a future family cannot
// compile as an accepted conversion checkpoint while bypassing registration. The guard adds
// no server schema, upload entry, synchronized row, optimistic projection,
// cleanup policy, hosted resource, migration execution, or production action.
