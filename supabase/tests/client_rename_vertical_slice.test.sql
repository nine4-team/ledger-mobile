-- DRAFT scaffold only: no executable rename assertions exist at this checkpoint.
-- The one passing placeholder keeps the repository-wide pgTAP runner valid.
--
-- After O-042/O-043 approval, implementation must cover the approved archived-
-- Client and same-value behavior plus exact cross-runtime display-name validity,
-- exact UInt64 command text, signed-bigint revision exhaustion, missing/stale/
-- future revisions, exact and changed replay, cross-command OperationID reuse,
-- malformed envelopes, byte-preserved Unicode names, monotonic revision/time,
-- Project-row immutability with joined current-name readback, direct-write
-- denial, owner/restricted/revoked/anonymous/cross-Account access, operation-
-- result non-enumeration, and true concurrent same-revision RPC calls where
-- exactly one mutating command applies. Restricted active same-Account members
-- retain existing reads but cannot rename or directly mutate. Exact replay must
-- work after a later chained overlay; unknown terminal codes must fail closed.

begin;

select plan(1);
select pass('DRAFT scaffold; executable rename requires O-042/O-043 and READY');
select * from finish();

rollback;
