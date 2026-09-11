# Capability Evolution Method

Status: required guidance before target mapping or implementation

## Purpose

The Firebase source inventory prevents accidental omission. It is not a design
specification for the Supabase/PowerSync application. Ledger must preserve
valuable user capabilities and historical evidence while deliberately
correcting defects, removing accidental backend mechanics, and improving
reliability, maintainability, security, and offline behavior.

The unit of comparison is a user or operational capability—not a Firestore
document, query, listener, Cloud Function, SDK type, or source file.

## Three Inputs, Three Different Questions

| Input | Question it answers | It does not automatically decide |
|---|---|---|
| Running source code and production profile | What does Ledger actually do and contain today? | Whether that behavior is desirable |
| Canonical specs and redesign decisions | What should Ledger do for users? | Whether every statement is current, internally consistent, or technically safe |
| Architecture and quality requirements | How must the target behave under offline use, failure, concurrency, authorization, migration, and operations? | New product policy where product authority is open |

No input silently overrides another. A disagreement becomes a recorded product,
architecture, migration, or defect decision.

## Required Capability Dossier

Before a target port, table, command, query, Sync Stream, or screen is treated
as ready, its capability dossier must record:

1. capability name and user/operational outcome;
2. every source surface and data shape that participates;
3. observed current behavior, including offline and failure behavior;
4. governing spec and decision IDs, with any suspected stale or contradictory
   text called out;
5. behavior classification using the taxonomy below;
6. target observable contract, without vendor mechanics;
7. migration and compatibility implications;
8. security, local-data, and Sync Stream requirements;
9. acceptance, offline, fault, migration, and reconciliation tests; and
10. unresolved questions that block schema or implementation.

Every source surface must also resolve through its classification batch in
`product-authority-crosswalk.json`. That cross-reference identifies the full
review set and the authority role of each document. It is deliberately not a
claim that a source file maps one-to-one to one spec paragraph; exact behavioral
requirements remain in the dossier, decision traceability, target mapping, and
acceptance tests.

### Behavior taxonomy

| Classification | Meaning | Typical manifest disposition |
|---|---|---|
| Preserve | User-visible outcome and semantics remain materially the same | `preserve` or `replace` |
| Correct | Current behavior is a demonstrated defect, security weakness, data-integrity risk, or contradiction with approved product authority | `replace`; `redesign` if externally observable policy changes |
| Improve | Same product outcome receives stronger offline, performance, operability, maintainability, or usability characteristics | usually `replace` |
| Redesign | Approved product behavior intentionally changes | `redesign` |
| Retire | Capability or data is deliberately removed with compatibility/evidence handling | `retire` |
| Open | Evidence or product authority is insufficient to decide | remain `blocked` or unmapped |

“Correct” and “improve” are dossier decisions, not excuses to invent product
behavior. A security or data-integrity defect may be corrected directly when
the required outcome is unambiguous; product-facing tradeoffs remain explicit
decisions.

## Parity Rule

Parity means the target passes the approved observable capability contract and
migrates all required evidence. It does not mean:

- reproducing Firestore collection/query shapes;
- preserving unordered pagination, broad listeners, or client-side scans;
- retaining fire-and-forget success reporting or suppressed server failures;
- copying authorization bypasses, globally open media, or stale derived state;
- retaining duplicate writers or per-client accounting implementations; or
- matching SDK timing, callbacks, intermediate snapshots, or error strings.

When current behavior is intentionally not preserved, the dossier must link the
reason and target acceptance test. This prevents both accidental feature loss
and accidental defect preservation.

## Spec Freshness Rule

Canonical specs remain product authority, but they are not assumed infallible.
During a dossier review:

1. compare the spec with the decision log and current source behavior;
2. identify superseded language, contradictions, missing edge cases, and
   behavior the spec never covered;
3. update the canonical spec and changelog when authority is clear;
4. otherwise add an explicit open decision and block dependent design; and
5. never resolve a discrepancy only inside architecture or implementation code.

The crosswalk roles enforce precedence: `canonical_target` and confirmed
decision-log entries define redesigned behavior; `current_product` and
`historical_evidence` can establish shipped behavior, constraints, fixtures, or
migration evidence but cannot silently become target authority.

## Target-Readiness Gate

A capability may advance from current-behavior characterization to target
mapping only when:

- its complete source-surface set is linked;
- its intended observable behavior is classified;
- preserved behavior and deliberate changes are distinguishable;
- stale/contradictory spec concerns are resolved or named blockers;
- offline, security, migration, and failure obligations are stated; and
- acceptance tests can detect both feature loss and reproduction of known
  defects.

A vertical spike may explore a technical uncertainty before this gate, but it
must use synthetic/isolated data and cannot establish product authority.

## Review Outcome

Each dossier ends with one of:

- **ready for target mapping**;
- **ready for a bounded technical spike**;
- **blocked on production evidence**;
- **blocked on product/spec decision**; or
- **retire with approved compatibility handling**.

The conversion manifest tracks coverage and evidence. The dossier owns the
reasoned transition from observed source behavior to the intended target
capability.
