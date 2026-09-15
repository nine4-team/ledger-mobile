begin;
select no_plan();

insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('receipt-project','account-primary','client-existing','Receipt project',now(),now(),1,1,'principal-owner');
insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values ('receipt-category','account-primary','Receipt category','fee','company_financial',40,'active',false,false,1,1);
insert into public.spike_items(id,account_id,description,created_by_principal_id,source,current_source)
values ('receipt-item-a','account-primary','Original Item A','principal-owner',null,null),
       ('receipt-item-b','account-primary','Original Item B','principal-owner','Original vendor','Display vendor'),
       ('receipt-foreign-item','account-other','Other Item','principal-other',null,null);
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
values ('receipt-current-space','account-primary','business_inventory',null,'Current storage','active');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,space_id,started_at,started_by_principal_id)
values ('receipt-current-placement','account-primary','receipt-item-b','business_inventory','receipt-current-space','2026-09-01','principal-owner');
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values ('receipt-item-b','account-primary','receipt-item-b',1,0);
select ledger_private.import_client_payment('receipt-collected-payment','account-primary','receipt-project',
  'client-existing',3050,'USD','synthetic-receipt','collected-payment','\x01'::bytea);
create temp table receipt_payment_before as select to_jsonb(t) as value from public.spike_transactions t where id='receipt-collected-payment';
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency,origin,scope_kind,category_id,non_item_receipt_lines)
values ('receipt-vendor','account-primary','receipt-project','client-existing',3050,'USD','vendor_payment','project','receipt-category',
  '[{"id":"tax","description":"Sales Tax","amountMinorUnits":"100","effect":"increase","quantity":"10"},
    {"id":"discount","description":"Discount","amountMinorUnits":"50","effect":"decrease"}]');
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values ('receipt-inventory','account-primary',100,'USD','return','vendor_payment','business_inventory','category-system');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('receipt-link-a','account-primary','receipt-vendor','receipt-item-a','USD',1000,'linked'),
       ('receipt-link-b','account-primary','receipt-vendor','receipt-item-b','USD',2000,'sold');
select is((select count(*) from public.transaction_receipt_items where transaction_id='receipt-vendor'
 and sync_scope_kind='project' and sync_project_id='receipt-project' and sync_category_id='receipt-category'),
 2::bigint,'receipt relationships carry exact derived parent routing');
update public.transaction_receipt_items set sync_scope_kind='business_inventory',sync_project_id=null,
 sync_category_id='category-system' where transaction_id='receipt-vendor';
select is((select count(*) from public.transaction_receipt_items where transaction_id='receipt-vendor'
 and sync_scope_kind='project' and sync_project_id='receipt-project' and sync_category_id='receipt-category'),
 2::bigint,'direct shadow-field writes cannot forge receipt routing');
update public.spike_transactions set scope_kind='business_inventory',project_id=null,client_id=null,
 category_id='category-system' where id='receipt-vendor';
select is((select count(*) from public.transaction_receipt_items where transaction_id='receipt-vendor'
 and sync_scope_kind='business_inventory' and sync_project_id is null and sync_category_id='category-system'),
 2::bigint,'scope and category changes reroute every receipt relationship atomically');
select is((select sum(amount_minor_units) from public.transaction_receipt_items where transaction_id='receipt-vendor'),
 3000::numeric,'routing propagation never changes recorded Item amounts');
update public.spike_transactions set scope_kind='project',project_id='receipt-project',client_id='client-existing',
 category_id='receipt-category' where id='receipt-vendor';
create temp table receipt_items_before as select jsonb_agg(to_jsonb(i) order by id) as value from public.spike_items i;
create temp table receipt_membership_before as select jsonb_agg(to_jsonb(i) order by id) as value from public.transaction_receipt_items i;

select throws_ok($$insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('receipt-bad-item','account-primary','receipt-vendor','receipt-foreign-item','USD',1,'linked')$$,
  '23503',null,'receipt Item must belong to the same Account');
select throws_ok($$insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('receipt-bad-payment','account-primary','receipt-collected-payment','receipt-item-a','USD',1,'linked')$$,
  '23503',null,'collection payment is not vendor receipt evidence');
select throws_ok($$insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('receipt-bad-currency','account-primary','receipt-inventory','receipt-item-a','EUR',1,'linked')$$,
  '23503',null,'receipt Item evidence uses the Transaction currency');
select throws_ok($$insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('receipt-duplicate','account-primary','receipt-vendor','receipt-item-a','USD',1000,'returned')$$,
  '23505',null,'one physical Item cannot be counted twice through another membership row');
select throws_ok($$insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values ('receipt-fake-invoice','account-primary','receipt-project','client-existing','receipt-vendor',1,'USD',3050)$$,
  '23514','Collected Invoice requires collection payment evidence','vendor Purchase cannot become Invoice collection evidence');
select ok(not has_any_column_privilege('anon','public.transaction_receipt_items','SELECT'),'anonymous role has no receipt Item read grant');
select ok(not has_any_column_privilege('service_role','public.transaction_receipt_items','SELECT'),'service role has no added receipt read bypass');
select ok(not has_table_privilege('authenticated','public.transaction_receipt_items','INSERT'),'no ordinary receipt Item writer was granted');
select ok(not has_function_privilege('anon','public.spike_read_transaction_receipt(text,text)','EXECUTE'),'anonymous RPC execution is not granted');

set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.spike_read_transaction_receipt('account-primary','receipt-vendor')$$,
  '28000','authentication required','missing identity cannot read');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_receipt('account-primary','receipt-vendor')$$,
  '42501','account_not_authorized','foreign Account cannot read');
select is((select count(*) from public.transaction_receipt_items),0::bigint,'foreign Account cannot bypass RPC through direct Item evidence reads');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_receipt('account-primary','receipt-vendor')$$,
  '42501','transaction_not_available','restricted member cannot read Fee receipt');
select is((select count(*) from public.transaction_receipt_items),0::bigint,'hidden Fee receipt cannot leak Item cost or count');
select is(public.spike_read_transaction_receipt('account-primary','receipt-inventory')->>'scopeKind','business_inventory','ordinary Inventory Return is readable without company-financial access');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->>'amountMinorUnits','3050','final amount is an exact string');
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->>'principalId','principal-owner','receipt snapshot identifies the authenticated principal');
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->'items',
  '[{"itemId":"receipt-item-a","amountMinorUnits":"1000","membershipKind":"linked","name":"Original Item A","sku":null,"source":null,"currentSource":null,"currentSpaceName":null,"imageCount":null},
    {"itemId":"receipt-item-b","amountMinorUnits":"2000","membershipKind":"sold","name":"Original Item B","sku":null,"source":"Original vendor","currentSource":"Display vendor","currentSpaceName":"Current storage","imageCount":"0"}]'::jsonb,
  'read includes current and historical Item price evidence once, with same-account Item labels');
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->'nonItemReceiptLines'->0->>'quantity','10','quantity remains source evidence, not an amount multiplier');
select throws_ok($$select public.spike_read_transaction_receipt('account-primary','receipt-collected-payment')$$,
  '42501','transaction_not_available','client payment is not substituted for ordinary receipt details');
select throws_ok($$select public.spike_read_transaction_receipt('account-primary','missing')$$,
  '42501','transaction_not_available','missing and inaccessible receipt have the same response');

-- Exercise the actual shared category command, not a special visibility writer.
select is((public.spike_manage_categories(jsonb_build_object(
  'operationId','category-management-' || encode(digest(convert_to('account-primary','UTF8'),'sha256'),'hex') || '-00000000-0000-4000-8000-000000000001',
  'accountId','account-primary','actorPrincipalId','principal-owner','contractVersion','category-management-v1',
  'clientCreatedAt',1789300000000,'preconditions','[]'::jsonb,'payload',jsonb_build_object(
    'action','edit','categoryId','receipt-category','expectedRevision','1','name','Receipt category',
    'kind','general','excludesFromOverallBudget',false))::text)).phase,'applied','Fee-to-General uses the ordinary category edit command');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->'category'->>'kind','general','current General category automatically permits the receipt');
select is((select count(*) from public.transaction_receipt_items),2::bigint,'Item evidence follows current category access with no sticky Fee rule');
reset role;
select is((select to_jsonb(t) from public.spike_transactions t where id='receipt-collected-payment'),
  (select value from receipt_payment_before),'category change preserves existing payment bytes');
select is((select jsonb_agg(to_jsonb(i) order by id) from public.spike_items i),(select value from receipt_items_before),'category change preserves physical Item identity and values');
select is((select jsonb_agg(to_jsonb(i) order by id) from public.transaction_receipt_items i),(select value from receipt_membership_before),'category change preserves historical membership and prices');

update public.transaction_receipt_items set amount_minor_units=null where id='receipt-link-b';
set local role authenticated;
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->'items'->1->'amountMinorUnits','null'::jsonb,'missing Item price is explicit unknown, not zero');
reset role;
update public.spike_budget_categories set lifecycle='archived',kind='itemized' where id='receipt-category';
set local role authenticated;
select is(public.spike_read_transaction_receipt('account-primary','receipt-vendor')->'category'->>'kind','itemized','archived category still supplies current audit classification');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select throws_ok($$select public.spike_read_transaction_receipt('account-primary','receipt-vendor')$$,
  '42501','account_not_authorized','removed member cannot read');
select is((select count(*) from public.transaction_receipt_items),0::bigint,'direct receipt evidence also denies removed membership');
reset role;
select ok(not ledger_private.valid_non_item_receipt_lines('[{"id":"x","description":"Tax","amountMinorUnits":"1","effect":"increase"},{"id":"x","description":"Tax","amountMinorUnits":"1","effect":"increase"}]'),'duplicate receipt line IDs rejected');
select ok(not ledger_private.valid_non_item_receipt_lines('[{"id":"x","description":"Tax","amountMinorUnits":"9223372036854775808","effect":"increase"}]'),'overflowing line magnitude rejected');
select ok(not ledger_private.valid_non_item_receipt_lines('[{"id":"x","description":"Tax","amountMinorUnits":"0","effect":"increase"}]'),'zero magnitude rejected, not silently normalized');
select ok(not ledger_private.valid_non_item_receipt_lines('[{"id":"x","description":"Tax","amountMinorUnits":"1","effect":"unknown"}]'),'unknown line effect rejected');
select * from finish();
rollback;
