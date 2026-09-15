begin;
select no_plan();
select is((select count(*) from pg_class where oid in ('public.transaction_attachment_sets'::regclass,
 'public.transaction_attachment_references'::regclass) and relrowsecurity and relforcerowsecurity),2::bigint,
 'both public attachment tables enable and force RLS');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='ledger_private' and p.proname in ('check_item_image_media_type','check_transaction_attachment_set','guard_transaction_attachment_parent')
 and p.prosecdef=(p.proname='check_transaction_attachment_set') and p.proconfig @> array['search_path=""']
 and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE')
 and not has_function_privilege('service_role',p.oid,'EXECUTE')),3::bigint,
 'private validators have exact intended authority, empty search path and no API access');
insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values ('tx-media-fee','account-primary','Private media fee','fee','company_financial',40,'active',false,false,1,1);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values ('tx-media-visible','account-primary',100,'USD','purchase','vendor_payment','business_inventory','category-furnishings'),
 ('tx-media-private','account-primary',100,'USD','purchase','vendor_payment','business_inventory','tx-media-fee');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
values ('tx-media-pdf','account-primary',repeat('a',64),123,'application/pdf','accounts/account-primary/attachments/tx-media-pdf/'||repeat('a',64)),
 ('tx-media-private-image','account-primary',repeat('b',64),456,'image/png','accounts/account-primary/attachments/tx-media-private-image/'||repeat('b',64)),
 ('tx-media-old-image','account-primary',repeat('c',64),789,'image/jpeg','accounts/account-primary/attachments/tx-media-old-image/'||repeat('c',64)),
 ('tx-media-foreign-image','account-other',repeat('d',64),789,'image/jpeg','accounts/account-other/attachments/tx-media-foreign-image/'||repeat('d',64));
insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
values ('tx-media-visible-set','account-primary','tx-media-visible','receipts',2,1),
 ('tx-media-other-set','account-primary','tx-media-visible','other',1,0),
 ('tx-media-private-set','account-primary','tx-media-private','receipts',1,1);
insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary,file_name)
values ('tx-media-current-ref','account-primary','tx-media-visible','receipts','tx-media-pdf',2,0,true,'Receipt.pdf'),
 ('tx-media-old-ref','account-primary','tx-media-visible','receipts','tx-media-old-image',1,0,true,'Old receipt.jpg'),
 ('tx-media-private-ref','account-primary','tx-media-private','receipts','tx-media-private-image',1,0,true,null);
insert into storage.objects(bucket_id,name) select 'ledger-attachments',storage_path from public.item_image_objects where id like 'tx-media-%';
set constraints all immediate;
select is((select sync_scope_kind from public.transaction_attachment_sets where id='tx-media-visible-set'),
 'business_inventory','marker routing derives from the canonical Transaction');
select is((select sync_category_id from public.transaction_attachment_references where id='tx-media-current-ref'),
 'category-furnishings','reference routing derives the exact current category');
select is((select count(*) from public.transaction_attachment_references where id like 'tx-media-%' and sync_is_current),
 2::bigint,'derived current reference filter excludes retained old revisions');
select is((select sync_byte_count from public.transaction_attachment_references where id='tx-media-current-ref'),
 123::bigint,'reference descriptor copies immutable exact object evidence');
update public.transaction_attachment_references set sync_scope_kind='project',sync_project_id='forged',
 sync_category_id='tx-media-fee',sync_is_current=false,sync_content_sha256=repeat('f',64),sync_byte_count=1,
 sync_media_type='text/html',sync_storage_path='forged' where id='tx-media-current-ref';
select ok((select sync_scope_kind='business_inventory' and sync_project_id is null
 and sync_category_id='category-furnishings' and sync_is_current and sync_content_sha256=repeat('a',64)
 and sync_byte_count=123 and sync_media_type='application/pdf'
 and sync_storage_path='accounts/account-primary/attachments/tx-media-pdf/'||repeat('a',64)
 from public.transaction_attachment_references where id='tx-media-current-ref'),
 'even a privileged direct write cannot forge derived routing or object evidence');
update public.spike_transactions set category_id='tx-media-fee' where id='tx-media-visible';
select is((select count(*) from public.transaction_attachment_sets where transaction_id='tx-media-visible' and sync_category_id='tx-media-fee'),
 2::bigint,'Transaction recategorization updates all section routing atomically');
select is((select count(*) from public.transaction_attachment_references where transaction_id='tx-media-visible' and sync_category_id='tx-media-fee'),
 2::bigint,'Transaction recategorization updates current and retained references');
update public.spike_transactions set category_id='category-furnishings' where id='tx-media-visible';
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('tx-media-project','account-primary','client-existing','Routing fixture',now(),now(),1,1,'principal-owner');
update public.spike_transactions set scope_kind='project',project_id='tx-media-project',client_id='client-existing'
 where id='tx-media-visible';
select is((select count(*) from public.transaction_attachment_references where transaction_id='tx-media-visible'
 and sync_scope_kind='project' and sync_project_id='tx-media-project'),2::bigint,
 'moving the canonical Transaction routes current and historical attachment evidence to the exact Project');
update public.spike_transactions set scope_kind='business_inventory',project_id=null,client_id=null where id='tx-media-visible';
update public.transaction_attachment_sets set revision=3,expected_count=0 where id='tx-media-visible-set';
select is((select count(*) from public.transaction_attachment_references where transaction_id='tx-media-visible' and sync_is_current),
 0::bigint,'new empty revision withdraws every prior current reference without deleting history');
update public.transaction_attachment_sets set revision=2,expected_count=1 where id='tx-media-visible-set';
select is((select count(*) from public.transaction_attachment_references where transaction_id='tx-media-visible' and sync_is_current),
 1::bigint,'derived current status always follows the authoritative marker');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='ledger_private' and p.proname in ('derive_transaction_sync_scope',
 'derive_transaction_attachment_sync_reference','propagate_transaction_sync_scope','propagate_transaction_attachment_sync_marker')
 and p.prosecdef=(p.proname<>'propagate_transaction_sync_scope') and p.proconfig @> array['search_path=""']
 and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE')
 and not has_function_privilege('service_role',p.oid,'EXECUTE')),4::bigint,
 'derived routing helpers have exact intended authority and remain inaccessible to API callers');
select ok(not has_table_privilege('authenticated','public.transaction_attachment_references','INSERT,UPDATE,DELETE'),'read path grants no attachment mutation');
select ok(not has_table_privilege('anon','public.transaction_attachment_sets','SELECT'),'anonymous has no attachment catalog grant');
select throws_ok($$update public.transaction_attachment_sets set transaction_id='tx-media-private' where id='tx-media-visible-set'$$,
 '55000','Transaction attachment parent identity is immutable','parent cannot be rebound');
select throws_ok($$insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
 values('tx-media-cross-account','account-other','tx-media-visible','other',1,0)$$,'23503',null,'set cannot substitute another Account');
select throws_ok($$insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary)
 values('tx-media-cross-object','account-primary','tx-media-visible','receipts','tx-media-foreign-image',2,1,false)$$,'23503',null,'reference cannot substitute another Account object');
select throws_ok($$update public.transaction_attachment_sets set expected_count=2 where id='tx-media-visible-set'$$,
 '23514','Current Transaction attachment set is inconsistent','incomplete publication cannot claim a complete set');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('tx-media-item','account-primary','Image-only Item','principal-owner');
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values('tx-media-item','account-primary','tx-media-item',1,0);
select throws_ok($$insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
 values('tx-media-invalid-item-pdf','account-primary','tx-media-item','tx-media-pdf',1,0,true)$$,
 '23514','Item image references require image media','shared PDF storage does not relax Item image rules');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_sets where transaction_id like 'tx-media-%'),3::bigint,'full member sees both Transaction catalogs and explicit empty other set');
select is((select count(*) from public.transaction_attachment_references where transaction_id like 'tx-media-%'),2::bigint,'full member sees current references only');
select is((select file_name from public.transaction_attachment_references where id='tx-media-current-ref'),'Receipt.pdf','filename is retained metadata, not identity');
select is((select count(*) from public.item_image_objects where id like 'tx-media-%'),2::bigint,'only objects with currently authorized relationships are visible');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/tx-media-%'),2::bigint,'private GET follows authorized current reference');
select set_config('storage.operation','storage.object.get_authenticated_info',true);
select is((select count(*) from storage.objects where name like '%/tx-media-%'),2::bigint,'hosted authenticated info follows the same current references');
select set_config('storage.operation','storage.object.sign',true);
select is((select count(*) from storage.objects where name like '%/tx-media-%'),0::bigint,'read does not enable signed URLs');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/tx-media-%'),0::bigint,'read does not enable object listing');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_sets where transaction_id like 'tx-media-%'),2::bigint,'limited member sees only the ordinary Transaction sections');
select is((select count(*) from public.transaction_attachment_references where transaction_id like 'tx-media-%'),1::bigint,'limited member cannot see Fee attachment metadata');
select is((select count(*) from public.item_image_objects where id like 'tx-media-%'),1::bigint,'limited member cannot bypass parent through object metadata');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/tx-media-%'),1::bigint,'limited member gets ordinary receipt bytes only');
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_sets where account_id='account-primary'),0::bigint,'foreign principal sees no Transaction catalogs');
select is((select count(*) from storage.objects where name like '%/tx-media-%'),0::bigint,'foreign object without a live reference is not downloadable');
select set_config('storage.operation','object.get_authenticated_info',true);
select is((select count(*) from storage.objects where name like '%/tx-media-%'),0::bigint,'authenticated info cannot cross Account boundaries');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_sets where account_id='account-primary'),0::bigint,'same JWT loses catalogs on Account removal');
select is((select count(*) from public.transaction_attachment_references where account_id='account-primary'),0::bigint,'same JWT loses references on Account removal');
select is((select count(*) from storage.objects where name like '%/tx-media-%'),0::bigint,'same JWT loses receipt bytes on Account removal');
select * from finish();
rollback;
