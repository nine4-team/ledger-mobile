begin;
select no_plan();
select ok((select relrowsecurity and relforcerowsecurity from pg_class
 where oid='public.transaction_attachment_upload_results'::regclass),'durable results enable and force RLS');
select ok(not has_table_privilege('anon','public.transaction_attachment_upload_results','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('authenticated','public.transaction_attachment_upload_results','INSERT,UPDATE,DELETE')
 and not has_table_privilege('service_role','public.transaction_attachment_upload_results','SELECT,INSERT,UPDATE,DELETE'),
 'results expose uploader-scoped authenticated read but no direct mutation or service table grant');
select ok(not has_function_privilege('anon',
 'public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)','EXECUTE')
 and not has_function_privilege('authenticated',
 'public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)','EXECUTE')
 and has_function_privilege('service_role',
 'public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)','EXECUTE'),
 'only the server verifier can invoke publication');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid=
 'public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)'::regprocedure),
 'service-only publisher is a locked-search-path definer');

insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,
 lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values('publication-fee','account-primary','Publication fee','fee','company_financial',45,'active',false,false,1,1);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values('publication-parent','account-primary',100,'USD','purchase','vendor_payment','business_inventory','category-furnishings'),
 ('publication-private','account-primary',100,'USD','purchase','vendor_payment','business_inventory','publication-fee'),
 ('publication-full','account-primary',100,'USD','purchase','vendor_payment','business_inventory','category-furnishings');
insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
values('publication-set','account-primary','publication-parent','receipts',1,0),
 ('publication-private-set','account-primary','publication-private','receipts',1,0),
 ('publication-full-set','account-primary','publication-full','receipts',1,0);

create function pg_temp.reserve(id text,parent text default 'publication-parent',principal text default 'principal-owner',
 local_position bigint default 0,primary_if_empty boolean default true,hash text default repeat('a',64)) returns void
language plpgsql as $$ begin
 insert into public.transaction_attachment_uploads(id,account_id,principal_id,transaction_id,section,
   content_sha256,byte_count,media_type,file_name,local_position,make_primary_if_empty)
 values(id,'account-primary',principal,parent,'receipts',hash,12,'image/png',id||'.png',local_position,primary_if_empty);
end $$;
create function pg_temp.object_for(id text,hash text default repeat('a',64)) returns void
language plpgsql as $$ begin
 insert into storage.objects(bucket_id,name,metadata) values('ledger-attachments',
   'accounts/account-primary/attachments/'||id||'/'||hash,'{"size":12,"mimetype":"image/png"}');
end $$;

select pg_temp.reserve('publication-one',local_position=>4294967295);
select pg_temp.object_for('publication-one');
set local role service_role;
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-one',repeat('a',64),12,'image/png')->>'phase'),
 'applied','UInt32 maximum position is bounded before narrowing and publishes atomically');
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-one',repeat('f',64),999,'text/html')->>'phase'),
 'applied','exact retry returns immutable applied result without reinterpreting observations');
reset role;
select is((select row(revision,expected_count)::text from public.transaction_attachment_sets where id='publication-set'),
 '(2,1)','first publication advances one coherent set revision');
select is((select row(id,attachment_id,set_revision,position,is_primary,file_name)::text
 from public.transaction_attachment_references where id='publication-one'),
 '(publication-one,publication-one,2,0,t,publication-one.png)','stable capture ID and first-primary intent become the reference');
select is((select row(account_id,content_sha256,byte_count,media_type,storage_path)::text
 from public.item_image_objects where id='publication-one'),
 '(account-primary,'||repeat('a',64)||',12,image/png,accounts/account-primary/attachments/publication-one/'||repeat('a',64)||')',
 'published immutable object descriptor matches verified reservation');

select pg_temp.reserve('publication-two',local_position=>0,primary_if_empty=>false,hash=>repeat('b',64));
select pg_temp.object_for('publication-two',repeat('b',64));
set local role service_role;
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-two',repeat('b',64),12,'image/png')->>'reference_position'),
 '0','later local order intent inserts at its bounded position');
reset role;
select is((select row(revision,expected_count)::text from public.transaction_attachment_sets where id='publication-set'),
 '(3,2)','second publication advances exactly once');
select results_eq($$select id,position,is_primary from public.transaction_attachment_references
 where transaction_id='publication-parent' and set_revision=3 order by position$$,
 $$select * from (values('publication-two',0,false),('publication-one',1,true)) expected(id,position,is_primary)$$,
 'existing primary is retained while positions remain contiguous');

select pg_temp.reserve('publication-mismatch',hash=>repeat('c',64));
select pg_temp.object_for('publication-mismatch',repeat('c',64));
set local role service_role;
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-mismatch',repeat('d',64),12,'image/png')->>'error_code'),
 'stored_bytes_mismatch','server-observed mismatch is durably rejected');
reset role;
select is((select count(*) from public.item_image_objects where id='publication-mismatch'),0::bigint,
 'mismatched bytes publish no object descriptor');

select pg_temp.reserve('publication-missing',hash=>repeat('d',64));
set local role service_role;
select throws_ok($$select public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-missing',repeat('d',64),12,'image/png')$$,
 'PT409','attachment_upload_incomplete','missing bytes remain retryable and create no terminal result');
reset role;
select is((select count(*) from public.transaction_attachment_upload_results where upload_id='publication-missing'),0::bigint,
 'missing bytes do not poison the durable upload identity');
select pg_temp.object_for('publication-missing',repeat('d',64));
set local role service_role;
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-missing',repeat('d',64),12,'image/png')->>'phase'),
 'applied','the same upload publishes after its missing bytes arrive');
reset role;
set local role service_role;
select throws_ok($$select public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000002','publication-one',repeat('a',64),12,'image/png')$$,
 '42501','attachment_upload_unavailable','another user cannot replay or inspect a result');
reset role;

select pg_temp.reserve('publication-private-one','publication-private','principal-restricted');
select pg_temp.object_for('publication-private-one');
set local role service_role;
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000002','publication-private-one',repeat('a',64),12,'image/png')->>'error_code'),
 'attachment_access_withdrawn','current financial visibility is rechecked at publication');
reset role;

insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select 'publication-occupied-'||n,'account-primary',repeat('f',64),1,'image/png',
 'accounts/account-primary/attachments/publication-occupied-'||n||'/'||repeat('f',64) from generate_series(1,50)n;
insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary)
select 'publication-occupied-ref-'||n,'account-primary','publication-full','receipts','publication-occupied-'||n,1,n-1,n=1
 from generate_series(1,50)n;
update public.transaction_attachment_sets set expected_count=50 where id='publication-full-set';
set constraints all immediate;
select pg_temp.reserve('publication-overflow','publication-full');
select pg_temp.object_for('publication-overflow');
set local role service_role;
select is((public.spike_publish_verified_transaction_attachment(
 '10000000-0000-0000-0000-000000000001','publication-overflow',repeat('a',64),12,'image/png')->>'error_code'),
 'attachment_section_full','publication rechecks the final fifty-file limit atomically');
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_upload_results where upload_id='publication-one'),1::bigint,
 'uploader can read durable applied result while authorized');
select throws_ok($$update public.transaction_attachment_upload_results set result_code='forged' where upload_id='publication-one'$$,
 '42501',null,'uploader cannot mutate a result');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.transaction_attachment_upload_results where upload_id='publication-one'),0::bigint,
 'same-Account second principal cannot read uploader result');
reset role;
select throws_ok($$update public.transaction_attachment_upload_results set result_code='forged' where upload_id='publication-one'$$,
 '55000','Attachment upload result is immutable','database owner cannot rewrite terminal evidence');

select * from finish();
rollback;
