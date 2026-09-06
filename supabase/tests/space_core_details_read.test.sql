-- READY scaffold only: no executable Space core-details assertion exists here.
-- The one passing placeholder keeps the repository-wide pgTAP runner valid.
--
-- Implementation must prove an untouched seven-column base relation, separate
-- one-to-one detail and relational children, scoped identity, UInt32 order
-- bounds, active-membership isolation, least privilege, indexed exact-Space
-- reads, active/archived and archived-Project parity, empty hierarchies, and
-- absence of mutation surfaces.

begin;

select plan(1);
select pass('READY scaffold; executable Space core-details proof is pending implementation');
select * from finish();

rollback;
