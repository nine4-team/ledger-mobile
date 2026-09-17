begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,created_by_principal_id)
 values('movement-import-item','account-primary','Source movement fixture','principal-owner');
insert into ledger_private.imported_item_movement_sources
 (account_id,item_id,source_account_id,source_item_id,source_document_id,source_bytes)
 values('account-primary','movement-import-item','source-account','source-item','source-edge',convert_to('{"retained":"exact evidence"}','UTF8'));
select is((select convert_from(source_bytes,'UTF8') from ledger_private.imported_item_movement_sources where source_document_id='source-edge'),
 '{"retained":"exact evidence"}','Source bytes preserved without movement interpretation');
select is((select source_sha256 from ledger_private.imported_item_movement_sources where source_document_id='source-edge'),
 extensions.digest(convert_to('{"retained":"exact evidence"}','UTF8'),'sha256'),'Stored hash matches exact bytes');
select throws_ok($$update ledger_private.imported_item_movement_sources set source_bytes='\x02' where source_document_id='source-edge'$$,
 '55000',null,'Source cannot be rewritten');
select throws_ok($$delete from ledger_private.imported_item_movement_sources where source_document_id='source-edge'$$,
 '55000',null,'Source cannot be discarded');
select throws_ok($$truncate ledger_private.imported_item_movement_sources$$,'55000',null,'Source cannot be truncated');
select throws_ok($$insert into ledger_private.imported_item_movement_sources
 (account_id,item_id,source_account_id,source_item_id,source_document_id,source_bytes)
 values('account-other','movement-import-item','source-account','source-item','other-edge','\x01')$$,
 '23503',null,'Source cannot bind to another Account Item');
select throws_ok($$insert into ledger_private.imported_item_movement_sources
 (account_id,item_id,source_account_id,source_item_id,source_document_id,source_bytes)
 values('account-primary','movement-import-item','source-account','source-item','source-edge','\x02')$$,
 '23505',null,'Source identity cannot silently be reused with changed bytes');
select ok(not has_table_privilege('anon','ledger_private.imported_item_movement_sources','SELECT,INSERT,UPDATE,DELETE'), 'No anonymous grants');
select ok(not has_table_privilege('authenticated','ledger_private.imported_item_movement_sources','SELECT,INSERT,UPDATE,DELETE'), 'No app grants');
select ok(not has_table_privilege('service_role','ledger_private.imported_item_movement_sources','SELECT,INSERT,UPDATE,DELETE'), 'No service API grants');
select is((select count(*) from public.spike_item_placements where item_id='movement-import-item'),0::bigint,
 'Retaining evidence does not fabricate a placement');
select throws_ok($$insert into ledger_private.imported_item_movement_sources
 (account_id,item_id,source_account_id,source_item_id,source_document_id,source_bytes,target_placement_id)
 values('account-primary','movement-import-item','source-account','source-item','unproven-placement','\x01','missing-placement')$$,
 '23503',null,'Imported movement cannot claim a nonexistent target interval');
select * from finish();
rollback;
