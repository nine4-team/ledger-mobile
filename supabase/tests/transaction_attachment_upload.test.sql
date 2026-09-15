begin;
select no_plan();
select ok((select relrowsecurity and relforcerowsecurity from pg_class
 where oid='public.transaction_attachment_uploads'::regclass),'reservations enable and force RLS');
select ok(not has_table_privilege('authenticated','public.transaction_attachment_uploads','UPDATE,DELETE'),
 'users cannot rewrite or delete immutable upload claims');
select ok(not has_column_privilege('authenticated','public.transaction_attachment_uploads','created_at','INSERT'),
 'server owns reservation timestamp');
select ok(not has_table_privilege('anon','public.transaction_attachment_uploads','SELECT,INSERT'),
 'anonymous cannot access reservations');
select ok(not has_table_privilege('service_role','public.transaction_attachment_uploads','SELECT,INSERT'),
 'no broad service-role reservation grants');
select ok((select not prosecdef and proconfig @> array['search_path=""'] from pg_proc
 where oid='public.spike_begin_transaction_attachment_upload(text,text,text,text,text,bigint,text,text,bigint,boolean)'::regprocedure),
 'typed entry uses invoker RLS and empty search path');
select ok(not has_function_privilege('anon',
 'public.spike_begin_transaction_attachment_upload(text,text,text,text,text,bigint,text,text,bigint,boolean)','EXECUTE')
 and not has_function_privilege('service_role',
 'public.spike_begin_transaction_attachment_upload(text,text,text,text,text,bigint,text,text,bigint,boolean)','EXECUTE'),
 'RPC has no anonymous or service-role execution grant');

insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,
 lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values('upload-fee','account-primary','Restricted fee','fee','company_financial',44,'active',false,false,1,1);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values('upload-parent','account-primary',100,'USD','purchase','vendor_payment','business_inventory','category-furnishings'),
 ('upload-private','account-primary',100,'USD','purchase','vendor_payment','business_inventory','upload-fee');
insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
values('upload-set','account-primary','upload-parent','receipts',1,0),
 ('upload-other-set','account-primary','upload-parent','other',1,0),
 ('upload-private-set','account-primary','upload-private','receipts',1,0);

create function pg_temp.reserve(id text, parent text default 'upload-parent',
 section text default 'receipts', hash text default repeat('a',64), mime text default 'image/png',
 account text default 'account-primary') returns jsonb language sql security invoker as $$
 select public.spike_begin_transaction_attachment_upload(id,account,parent,section,hash,12,mime,'Original.png',0,true)
$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(pg_temp.reserve('upload-one')->>'phase','awaiting_upload','reservation does not claim verified or published');
select is(pg_temp.reserve('upload-one')->>'storagePath',
 'accounts/account-primary/attachments/upload-one/'||repeat('a',64),'exact retry returns canonical account-scoped path');
select is((select count(*) from public.transaction_attachment_uploads where id='upload-one'),1::bigint,'retry creates no duplicate');
select is((select count(*) from public.transaction_attachment_references where transaction_id='upload-parent'),0::bigint,
 'unverified reservation cannot appear in published gallery');
select throws_ok($$select pg_temp.reserve('upload-one','upload-parent','receipts',repeat('b',64))$$,
 'PT409','attachment_upload_identity_conflict','stable ID cannot replace checksum');
select throws_ok($$select pg_temp.reserve('upload-one','upload-parent','other')$$,
 'PT409','attachment_upload_identity_conflict','stable ID cannot change section');
select throws_ok($$select pg_temp.reserve('upload-html','upload-parent','receipts',repeat('a',64),'text/html')$$,
 '23514',null,'non-media upload refused');
select throws_ok($$select pg_temp.reserve('upload-other-pdf','upload-parent','other',repeat('a',64),'application/pdf')$$,
 '23514',null,'Other Images does not gain a PDF upload route');
select lives_ok($$select pg_temp.reserve('upload-pdf','upload-parent','receipts',repeat('a',64),'application/pdf')$$,
 'receipt PDF can reserve bytes');
select throws_ok($$select pg_temp.reserve('upload-cross','upload-parent','receipts',repeat('a',64),'image/png','account-other')$$,
 '42501',null,'cannot substitute another Account');
select throws_ok($$insert into public.transaction_attachment_uploads(id,account_id,principal_id,transaction_id,section,
 content_sha256,byte_count,media_type,local_position,make_primary_if_empty)
 values('upload-forged','account-primary','principal-restricted','upload-parent','receipts',repeat('a',64),12,'image/png',0,true)$$,
 '42501',null,'direct insert cannot impersonate another capturing principal');
select throws_ok($$update public.transaction_attachment_uploads set content_sha256=repeat('b',64) where id='upload-one'$$,
 '42501',null,'no direct reservation edit permission');
select throws_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/unreserved/'||repeat('a',64))$$,
 '42501',null,'unreserved Storage path denied');
select lives_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/upload-one/'||repeat('a',64))$$,
 'uploader can insert the exact reserved path (SQL policy evidence, not byte transfer)');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/upload-one/%'),1::bigint,'uploader can verify its unverified original');
with changed as (update storage.objects set metadata='{"forged":true}'
 where name like '%/upload-one/%' returning 1)
 select is(count(*),0::bigint,'reservation does not grant object overwrite') from changed;
select throws_ok($$delete from storage.objects where name like '%/upload-one/%'$$,
 '42501','Direct deletion from storage tables is not allowed. Use the Storage API instead.',
 'Storage rejects direct object deletion; the reservation grants no delete route');
select set_config('storage.operation','storage.object.sign',true);
select is((select count(*) from storage.objects where name like '%/upload-one/%'),0::bigint,'reservation grants no signed URL access');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/upload-one/%'),0::bigint,'reservation grants no object listing');
select set_config('storage.operation','storage.object.get_authenticated',true);

select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_uploads),0::bigint,'same-Account second principal cannot see unverified reservations');
select is((select count(*) from storage.objects where name like '%/upload-one/%'),0::bigint,'same-Account second principal cannot read unverified bytes');
select throws_ok($$select pg_temp.reserve('upload-one')$$,'42501',null,'other principal cannot replay an upload ID');
select throws_ok($$select pg_temp.reserve('upload-fee-denied','upload-private')$$,'42501',null,'financially hidden parent refuses upload');
select lives_ok($$select pg_temp.reserve('upload-member')$$,'ordinary authorized member retains capture permission');
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_uploads),0::bigint,'foreign Account principal sees none');

reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_uploads),0::bigint,'learned removal hides prior reservations');
select is((select count(*) from storage.objects where name like '%/upload-one/%'),0::bigint,'learned removal withdraws reserved-byte read');
select throws_ok($$select pg_temp.reserve('upload-removed')$$,'42501',null,'removed member cannot reserve');
select throws_ok($$insert into storage.objects(bucket_id,name)
 values('ledger-attachments','accounts/account-primary/attachments/upload-pdf/'||repeat('a',64))$$,
 '42501',null,'removal also rejects bytes for an already reserved path');
reset role;
update public.spike_account_memberships set state='active' where account_id='account-primary' and principal_id='principal-owner';

-- Fill a real, internally consistent section after reservation. Retrying that
-- reservation consumes no slot; new reservations must be refused at capacity.
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select 'upload-occupied-'||n,'account-primary',repeat('f',64),1,'image/png',
 'accounts/account-primary/attachments/upload-occupied-'||n||'/'||repeat('f',64) from generate_series(1,50) n;
insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary)
select 'upload-occupied-ref-'||n,'account-primary','upload-parent','receipts','upload-occupied-'||n,1,n-1,n=1
 from generate_series(1,50) n;
update public.transaction_attachment_sets set expected_count=50 where id='upload-set';
set constraints all immediate;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$select pg_temp.reserve('upload-one')$$,'retry remains readable after section fills');
select throws_ok($$select pg_temp.reserve('upload-full')$$,'42501',null,'new reservation refuses full section');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select pg_temp.reserve('upload-no-auth')$$,'28000','authentication_required','JWT identity required');
reset role;
select * from finish();
rollback;
