-- DRAFT scaffold only: no executable Space-creation assertions exist here.
-- The one passing placeholder keeps the repository-wide pgTAP runner valid.
--
-- The READY contract must require executable proof for Project and Business
-- Inventory creation, duplicate names, canonical name/notes bytes, exact
-- same-Account Project-parent validation, server-owned active lifecycle,
-- revision 1 and audit fields, exact replay, changed replay, identity races,
-- anonymous/revoked/cross-Account denial, direct-DML denial, and absence of
-- every unrelated Item/accounting/media/template/checklist/review side effect.

begin;

select plan(1);
select pass('DRAFT scaffold; executable Space creation requires O-044/O-045/O-046 and READY');
select * from finish();

rollback;
