begin;

select plan(1);

select pass(
  'Project archival-review READY scaffold is intentionally assertion-free'
);

select * from finish();
rollback;
