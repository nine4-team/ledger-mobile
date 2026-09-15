begin;
select no_plan();
select ok((select not prosecdef and proconfig @> array['search_path=""']
 from pg_proc where oid='public.spike_read_transaction_attachments(text,text,text,integer,integer,text)'::regprocedure),
 'attachment page is an invoker with an empty search path');
select ok(not has_function_privilege('anon','public.spike_read_transaction_attachments(text,text,text,integer,integer,text)','EXECUTE')
 and not has_function_privilege('service_role','public.spike_read_transaction_attachments(text,text,text,integer,integer,text)','EXECUTE'),
 'page grants no anonymous or service-role entry');
insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
 values('page-fee','account-primary','Page fee','fee','company_financial',42,'active',false,false,1,1);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
 values('page-visible','account-primary',1,'USD','purchase','vendor_payment','business_inventory','category-furnishings'),
 ('page-private','account-primary',1,'USD','purchase','vendor_payment','business_inventory','page-fee');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
 select 'page-object-'||n,'account-primary',repeat('a',64),1,'application/pdf',
 'accounts/account-primary/attachments/page-object-'||n||'/'||repeat('a',64) from generate_series(0,2) n;
insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
 values('page-set','account-primary','page-visible','receipts',9007199254740993,3),
 ('page-empty','account-primary','page-visible','other',1,0);
insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary,file_name)
 select 'page-ref-'||n,'account-primary','page-visible','receipts','page-object-'||n,9007199254740993,n,n=0,'Receipt '||n||'.pdf'
 from generate_series(0,2) n;
set constraints all immediate;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(public.spike_read_transaction_attachments('account-primary','page-visible','receipts',0,2),
 '{"accountId":"account-primary","principalId":"principal-owner","transactionId":"page-visible", "scopeKind":"business_inventory","projectId":null,"clientId":null,
 "section":"receipts","revision":"9007199254740993","expectedCount":3,"startPosition":0,"isComplete":false,"nextPosition":2,
 "attachments":[{"id":"page-ref-0","position":0,"isPrimary":true,"kind":"pdf","fileName":"Receipt 0.pdf"},
 {"id":"page-ref-1","position":1,"isPrimary":false,"kind":"pdf","fileName":"Receipt 1.pdf"}]}'::jsonb,
 'bounded first page keeps exact revision and exposes only public reference fields');
select is(public.spike_read_transaction_attachments('account-primary','page-visible','receipts',2,2,'9007199254740993')->'attachments',
 '[{"id":"page-ref-2","position":2,"isPrimary":false,"kind":"pdf","fileName":"Receipt 2.pdf"}]'::jsonb,
 'continuation returns remaining reference in exact order');
select is(public.spike_read_transaction_attachments('account-primary','page-visible','receipts',2,2,'9007199254740993')->'nextPosition',
 'null'::jsonb,'last page has no invented continuation');
select is(public.spike_read_transaction_attachments('account-primary','page-visible','receipts')->>'isComplete','true',
 'uncapped full section is complete');
select is(public.spike_read_transaction_attachments('account-primary','page-visible','other')->>'isComplete','true',
 'known empty is complete');
select is(public.spike_read_transaction_attachments('account-primary','page-private','other')->'revision','null'::jsonb,
 'missing marker stays unknown');
select is(public.spike_read_transaction_attachments('account-primary','page-private','other')->>'isComplete','false',
 'unknown is not an empty complete section');
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-visible','receipts',2,2,'2')$$,
 'PT409','transaction_attachment_revision_changed','stale continuation conflicts instead of mixing revisions');
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-visible','receipts',2)$$,
 '22023','transaction_attachment_page_invalid','continuation requires revision');
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-visible','receipts',0,101)$$,
 '22023','transaction_attachment_page_invalid','row cap is enforced by the authority');
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-visible','receipts',4,1,'9007199254740993')$$,
 '22023','transaction_attachment_page_invalid','out-of-range offset fails');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(public.spike_read_transaction_attachments('account-primary','page-visible','receipts')->>'expectedCount','3',
 'limited member retains allowed attachments');
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-private','receipts')$$,
 '42501','transaction_not_available','limited member cannot inspect Fee metadata, including unknown state');
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','missing','receipts')$$,
 '42501','transaction_not_available','missing and hidden use the same failure');
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-visible','receipts')$$,
 '42501','account_not_authorized','foreign Account is denied');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_attachments('account-primary','page-visible','receipts')$$,
 '42501','account_not_authorized','same JWT cannot page after membership removal');
select * from finish();
rollback;
