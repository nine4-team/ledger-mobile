-- DRAFT placeholder: prove the future vendor-suggestion schema, normalization and
-- ordering invariants, indexes, SELECT authorization matrix, and denied client writes.
-- Excludes executable coverage or authorization for any O-026 mutation.

begin;

select plan(1);
select * from skip(
  1,
  'DRAFT scaffold; executable Vendor suggestion assertions begin only after exact READY CI'
);
select * from finish();

rollback;
