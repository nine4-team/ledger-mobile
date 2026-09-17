-- Raw source provenance, not a second custody or accounting ledger.
create table ledger_private.imported_item_movement_sources (
  account_id text not null,
  item_id text not null,
  source_account_id text not null check(octet_length(source_account_id) between 1 and 1500),
  source_item_id text not null check(octet_length(source_item_id) between 1 and 1500),
  source_document_id text not null check(octet_length(source_document_id) between 1 and 1500),
  source_bytes bytea not null check(octet_length(source_bytes) between 1 and 4194304),
  target_placement_id text,
  source_sha256 bytea generated always as (extensions.digest(source_bytes,'sha256')) stored,
  primary key(source_account_id,source_document_id),
  foreign key(account_id,item_id) references public.spike_items(account_id,id),
  foreign key(account_id,target_placement_id,item_id) references public.spike_item_placements(account_id,id,item_id)
);
create index imported_item_movement_item_idx on ledger_private.imported_item_movement_sources(account_id,item_id);
create index imported_item_movement_placement_idx on ledger_private.imported_item_movement_sources(account_id,target_placement_id,item_id);
alter table ledger_private.imported_item_movement_sources enable row level security;
alter table ledger_private.imported_item_movement_sources force row level security;
revoke all on ledger_private.imported_item_movement_sources from public,anon,authenticated,service_role;
create trigger imported_item_movement_immutable before update or delete
  on ledger_private.imported_item_movement_sources for each row
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_item_movement_no_truncate before truncate
  on ledger_private.imported_item_movement_sources for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();
