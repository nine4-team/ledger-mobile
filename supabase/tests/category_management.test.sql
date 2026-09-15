begin;
select no_plan();
select is(normalize(lower('ΟΣ'), NFC), normalize(lower('ος'), NFC),
  'database comparison uses context-sensitive Greek final sigma');
select is(normalize(lower(U&'\0130'), NFC), normalize(lower(U&'i\0307'), NFC),
  'database comparison preserves dotted-I expansion');

create function pg_temp.category_command(key text, payload jsonb,
  actor text default 'principal-owner', account text default 'account-primary')
returns public.spike_operation_results language sql as $$
  select public.spike_manage_categories(jsonb_build_object(
    'operationId','category-management-' || encode(digest(convert_to(account,'UTF8'),'sha256'),'hex')
      || '-' || substring(md5(key),1,8) || '-' || substring(md5(key),9,4)
      || '-' || substring(md5(key),13,4) || '-' || substring(md5(key),17,4) || '-' || substring(md5(key),21,12),
    'accountId',account,'actorPrincipalId',actor,'contractVersion','category-management-v1',
    'clientCreatedAt',1789300000000,'preconditions','[]'::jsonb,'payload',payload)::text)
$$;

-- Collected evidence deliberately refers to a category that this test changes
-- from Fee to General. Current classification must not rewrite paid history.
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('category-frozen-project','account-primary','client-existing','Category frozen fixture',now(),now(),1,1,'principal-owner');
select ledger_private.import_client_payment('category-frozen-payment','account-primary','category-frozen-project',
  'client-existing',100,'USD','synthetic-category','frozen-payment','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values ('category-frozen-invoice','account-primary','category-frozen-project','client-existing','category-frozen-payment',1,'USD',100);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,
  source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values ('category-frozen-line','account-primary','category-frozen-invoice',0,'USD','fee_installment','category-frozen-fee',1,
  'category-design-fee',100,'Original collected Fee','{"categoryKind":"fee","description":"Original collected Fee"}');
update ledger_private.collected_invoices set sealed=true where id='category-frozen-invoice';
set constraints all immediate;
set constraints all deferred;
create temp table frozen_accounting_before as
select (select to_jsonb(i) from ledger_private.collected_invoices i where id='category-frozen-invoice') as invoice,
  (select to_jsonb(l) from ledger_private.collected_invoice_lines l where id='category-frozen-line') as line,
  (select to_jsonb(t) from public.spike_transactions t where id='category-frozen-payment') as payment;

create temp table accounting_before as select jsonb_agg(to_jsonb(a) order by a.id) as allocations
  from public.spike_project_category_allocations a;
grant select on accounting_before to authenticated;
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select pg_temp.category_command('unauth','{}')$$,'28000',
  'authentication required','unauthenticated request cannot reach data');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select pg_temp.category_command('spoof','{}')$$,'42501',
  'actor is not the authenticated principal','actor spoof denied');
select throws_ok($$select pg_temp.category_command('foreign','{}','principal-restricted','account-other')$$,
  '42501','active account membership required','cross-Account request denied before payload processing');
select throws_ok($$select public.spike_read_budget_categories('account-other')$$,
  '42501','account_not_authorized','category lookup refuses foreign Account instead of returning empty');
select is((public.spike_read_budget_categories('account-primary')->>'principalId'),'principal-restricted',
  'category lookup is bound to authenticated principal');
select is((select count(*) from jsonb_array_elements(public.spike_read_budget_categories('account-primary')->'categories') c
  where c->>'kind' = 'fee'), 0::bigint, 'lookup preserves Fee RLS for nonfinancial members');
select ok((select bool_and(jsonb_typeof(c->'revision') = 'string')
  from jsonb_array_elements(public.spike_read_budget_categories('account-primary')->'categories') c),
  'lookup transmits exact revision strings for MCP');
select is((pg_temp.category_command('member-create',
  '{"action":"create","categoryId":"category-test","name":"Art & Décor","kind":"general","excludesFromOverallBudget":false}',
  'principal-restricted')).phase,'applied','employee can create without project/client management grants');
select is((pg_temp.category_command('member-create',
  '{"action":"create","categoryId":"category-test","name":"Art & Décor","kind":"general","excludesFromOverallBudget":false}',
  'principal-restricted')).phase,'applied','exact replay returns original result');
select is((select revision from public.spike_budget_categories where id='category-test'),1::bigint,
  'replay creates no duplicate or revision bump');
select is((pg_temp.category_command('equivalent-unicode-name',
  jsonb_build_object('action','create','categoryId','unicode-duplicate','name',U&'ART & DE\0301COR',
    'kind','general','excludesFromOverallBudget',false),'principal-restricted')).error_code,
  'category_name_unavailable','canonically equivalent case-insensitive names cannot create duplicate categories');
select throws_ok($$select pg_temp.category_command('member-create',
  '{"action":"create","categoryId":"different-id","name":"Other","kind":"general","excludesFromOverallBudget":false}',
  'principal-restricted')$$,'22023','operation identity already used','different payload cannot reuse result identity');
select is((pg_temp.category_command('control-name-' || cp,
  jsonb_build_object('action','create','categoryId','control-name-' || cp,
    'name','Name' || chr(cp) || 'end','kind','general','excludesFromOverallBudget',false),
  'principal-restricted')).error_code, 'category_name_invalid',
  'reject Unicode control/format character U+' || to_hex(cp))
from unnest(array[1,31,127,159,173,1536,1541,1564,1757,1807,2192,2193,2274,6158,
  8203,8207,8234,8238,8288,8292,8294,8303,65279,65529,65531,69821,69837,
  78896,78911,113824,113827,119155,119162,917505,917536,917631]) cp;
select is((pg_temp.category_command('untrimmed-name-' || cp,
  jsonb_build_object('action','create','categoryId','untrimmed-name-' || cp,
    'name',chr(cp) || 'Name' || chr(cp),'kind','general','excludesFromOverallBudget',false),
  'principal-restricted')).error_code, 'category_name_invalid',
  'wire name must already be trimmed: U+' || to_hex(cp))
from unnest(array[9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,
  8198,8199,8200,8201,8202,8203,8232,8233,8239,8287,12288]) cp;
select is((pg_temp.category_command('hidden-edit',
  '{"action":"edit","categoryId":"category-design-fee","expectedRevision":"1","name":"Design Fee","kind":"general","excludesFromOverallBudget":true}',
  'principal-restricted')).error_code,'category_unavailable','cannot edit an unreadable Fee by knowing its ID');
select is((pg_temp.category_command('stale',
  '{"action":"archive","categoryId":"category-test","expectedRevision":"2"}',
  'principal-restricted')).error_code,'category_revision_conflict','stale write is durably rejected');
select is((pg_temp.category_command('system',
  '{"action":"archive","categoryId":"category-system","expectedRevision":"1"}',
  'principal-restricted')).error_code,'category_protected','system category remains protected');
select is((pg_temp.category_command('archive',
  '{"action":"archive","categoryId":"category-test","expectedRevision":"1"}',
  'principal-restricted')).phase,'applied','archive retains record');
select is((select lifecycle from public.spike_budget_categories where id='category-test'),'archived','archived state visible');
select is((pg_temp.category_command('duplicate',
  '{"action":"create","categoryId":"duplicate","name":"ART & DÉCOR","kind":"general","excludesFromOverallBudget":false}',
  'principal-restricted')).error_code,'category_name_unavailable','archived case-insensitive name stays reserved');
select is((pg_temp.category_command('archive-noop',
  '{"action":"archive","categoryId":"category-test","expectedRevision":"2"}',
  'principal-restricted')).phase,'applied','already archived operation is harmless');
select is((select revision from public.spike_budget_categories where id='category-test'),2::bigint,'no-op does not bump revision');
select is((pg_temp.category_command('restore',
  '{"action":"restore","categoryId":"category-test","expectedRevision":"2"}',
  'principal-restricted')).phase,'applied','restore uses same stable identity');

select is((pg_temp.category_command('incomplete-order',
  '{"action":"reorder","order":[{"categoryId":"category-test","expectedRevision":"3"}]}',
  'principal-restricted')).error_code,'category_order_invalid','partial order denied');
select is((pg_temp.category_command('reorder',
  '{"action":"reorder","order":[{"categoryId":"category-test","expectedRevision":"3"},{"categoryId":"category-furnishings","expectedRevision":"1"}]}',
  'principal-restricted')).phase,'applied','complete visible set swaps atomically without hidden Fee');
select is((select presentation_order from public.spike_budget_categories where id='category-test'),10::bigint,'first selected slot moved');
select is((select presentation_order from public.spike_budget_categories where id='category-furnishings'),31::bigint,'other selected slot moved');
select is((select presentation_order from public.spike_budget_categories where id='category-system'),30::bigint,'system slot untouched');
select is((select count(*) from public.spike_budget_categories where id='category-design-fee'),0::bigint,'Fee stays hidden');
select is((select count(*) from public.spike_operation_results
  where command_type='manage_categories' and subject_id <> account_id),0::bigint,
  'Account-visible operation results do not expose hidden category identities');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select presentation_order from public.spike_budget_categories where id='category-design-fee'),20::bigint,'hidden slot unchanged by member reorder');
select is((pg_temp.category_command('fee-general',
  '{"action":"edit","categoryId":"category-design-fee","expectedRevision":"1","name":"Design Fee","kind":"general","excludesFromOverallBudget":true}')).phase,
  'applied','explicit Fee to General edit allowed');
select is((select visibility_class from public.spike_budget_categories where id='category-design-fee'),'ordinary',
  'visibility projection derives from current General type');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.spike_budget_categories where id='category-design-fee'),1::bigint,
  'General is immediately readable by ordinary rules, no transition flag');

select is((pg_temp.category_command('general-itemized',
  '{"action":"edit","categoryId":"category-test","expectedRevision":"4","name":"Art & Décor","kind":"itemized","excludesFromOverallBudget":false}',
  'principal-restricted')).phase,'applied','General to Itemized uses same definition');
select is((select kind from public.spike_budget_categories where id='category-test'),'itemized','new type stored');
select is((pg_temp.category_command('itemized-general',
  '{"action":"edit","categoryId":"category-test","expectedRevision":"5","name":"Art & Décor","kind":"general","excludesFromOverallBudget":false}',
  'principal-restricted')).phase,'applied','Itemized to General is direct edit, no invented review workflow');
select throws_ok($$update public.spike_budget_categories set kind='fee' where id='category-test'$$,
  '42501','permission denied for table spike_budget_categories','direct writes remain denied');
select is((pg_temp.category_command('equivalent-spelling-edit',
  jsonb_build_object('action','edit','categoryId','category-test','expectedRevision','6',
    'name',U&'Art & De\0301cor','kind','general','excludesFromOverallBudget',false),
  'principal-restricted')).phase, 'applied', 'equivalent spelling can update its own category');
select is((select revision from public.spike_budget_categories where id='category-test'),7::bigint,
  'changed display bytes advance revision even when names are canonically equivalent');
select is((select convert_to(display_name,'UTF8') from public.spike_budget_categories where id='category-test'),
  convert_to(U&'Art & De\0301cor','UTF8'), 'saved display spelling retains exact bytes');
select is((pg_temp.category_command('noncontrol-variation-selector',
  jsonb_build_object('action','create','categoryId','noncontrol-variation-selector',
    'name',U&'Variation\+0E0101','kind','general','excludesFromOverallBudget',false),
  'principal-restricted')).phase, 'applied',
  'supplementary variation selector is not misclassified as a control character');

reset role;
select is((select to_jsonb(i) from ledger_private.collected_invoices i where id='category-frozen-invoice'),
  (select invoice from frozen_accounting_before),'category edits preserve the complete frozen Invoice record');
select is((select to_jsonb(l) from ledger_private.collected_invoice_lines l where id='category-frozen-line'),
  (select line from frozen_accounting_before),'current General classification preserves frozen Fee line and source evidence');
select is((select to_jsonb(t) from public.spike_transactions t where id='category-frozen-payment'),
  (select payment from frozen_accounting_before),'category edits preserve payment amount, identity and scope');
select is((select jsonb_agg(to_jsonb(a) order by a.id) from public.spike_project_category_allocations a),
  (select allocations from accounting_before),'category edits preserve existing allocation evidence');
-- No caller, including maintenance writers, can retain stale classification.
update public.spike_budget_categories set visibility_class='company_financial' where id='category-test';
select is((select visibility_class from public.spike_budget_categories where id='category-test'),'ordinary',
  'current kind wins over a stale supplied visibility value');
update public.spike_account_memberships set state='removed'
  where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select pg_temp.category_command('member-create',
  '{"action":"create","categoryId":"category-test","name":"Art & Décor","kind":"general","excludesFromOverallBudget":false}',
  'principal-restricted')$$,'42501','active account membership required','revocation denies replay before result access');
select throws_ok($$select public.spike_read_budget_categories('account-primary')$$,
  '42501','account_not_authorized','revocation denies category lookup');

-- Length fixtures run after ordering assertions so they do not change that
-- test's complete visible ordering set. All synthetic rows roll back below.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((pg_temp.category_command('length-100-' || label,
  jsonb_build_object('action','create','categoryId','length-100-' || label,
    'name',name,'kind','general','excludesFromOverallBudget',false))).phase,
  'applied','accept 100 Unicode code points: ' || label)
from (values ('ascii',repeat('a',100)), ('emoji',repeat('🪑',100)),
  ('combining',repeat(U&'e\0301',50))) names(label,name);
select is((pg_temp.category_command('length-101-' || label,
  jsonb_build_object('action','create','categoryId','length-101-' || label,
    'name',name || 'a','kind','general','excludesFromOverallBudget',false))).error_code,
  'category_name_invalid','reject 101 Unicode code points: ' || label)
from (values ('ascii',repeat('a',100)), ('emoji',repeat('🪑',100)),
  ('combining',repeat(U&'e\0301',50))) names(label,name);

reset role;
select ok(not has_function_privilege('anon','public.spike_manage_categories(text)','execute'),'anonymous RPC execution revoked');
select ok(not has_function_privilege('service_role','public.spike_manage_categories(text)','execute'),'service RPC execution not granted');
select ok(not has_function_privilege('anon','public.spike_read_budget_categories(text)','execute'),'anonymous lookup revoked');
select ok(not has_function_privilege('service_role','public.spike_read_budget_categories(text)','execute'),'service lookup not granted');
select * from finish();
rollback;
