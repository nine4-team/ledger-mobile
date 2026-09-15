begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('expense-upload-project','account-primary','client-existing','Expense upload',now(),now(),1,1,'principal-owner');
create function pg_temp.reserve_expense(id text, expense text default 'pending-expense',
  hash text default repeat('a',64), account text default 'account-primary')
returns jsonb language sql security invoker as $$
  select public.spike_begin_expense_attachment_upload(id,account,'expense-upload-project',expense,hash,12,'application/pdf','Receipt.pdf')
$$;
select ok(not has_table_privilege('authenticated','ledger_private.expense_attachment_uploads','SELECT,INSERT,UPDATE,DELETE'),
  'reservation table is private');
select ok(not has_function_privilege('anon','public.spike_begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text)','EXECUTE')
  and not has_function_privilege('service_role','public.spike_begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text)','EXECUTE'),
  'no anonymous or service role admission');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(pg_temp.reserve_expense('expense-upload-one')->>'phase','awaiting_upload','pending Expense can reserve before creation');
select is(pg_temp.reserve_expense('expense-upload-one')->>'storagePath',
  'accounts/account-primary/attachments/expense-upload-one/'||repeat('a',64),'exact retry retains path');
select throws_ok($$select pg_temp.reserve_expense('expense-upload-one','different-expense')$$,
  'PT409','expense_upload_identity_conflict','cannot replace Expense identity');
select throws_ok($$select pg_temp.reserve_expense('expense-upload-one','pending-expense',repeat('b',64))$$,
  'PT409','expense_upload_identity_conflict','cannot replace content');
select throws_ok($$select pg_temp.reserve_expense('expense-upload-foreign','pending-expense',repeat('a',64),'account-other')$$,
  '42501','expense_upload_unavailable','cross Account denied');
select lives_ok($$insert into storage.objects(bucket_id,name) values
  ('ledger-attachments','accounts/account-primary/attachments/expense-upload-one/'||repeat('a',64))$$,
  'exact reserved Storage insert allowed');
select throws_ok($$insert into storage.objects(bucket_id,name) values
  ('ledger-attachments','accounts/account-primary/attachments/expense-unreserved/'||repeat('a',64))$$,
  '42501',null,'unreserved bytes denied');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),1::bigint,'owner can read reserved bytes');
select set_config('storage.operation','storage.object.get_authenticated_info',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),1::bigint,'owner can inspect upload metadata');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),0::bigint,'reservation grants no listing');
select set_config('storage.operation','storage.object.sign',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),0::bigint,'reservation grants no signed URLs');
select set_config('storage.operation','storage.object.get_authenticated',true);
with changed as (update storage.objects set metadata='{"forged":true}' where name like '%/expense-upload-one/%' returning 1)
select is(count(*),0::bigint,'reservation grants no overwrite') from changed;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),0::bigint,'another member cannot read pending bytes');
reset role;
select is((select count(*) from ledger_private.expense_attachment_uploads where id='expense-upload-one'),1::bigint,'retry creates one reservation');
select is((select count(*) from ledger_private.expenses where id='pending-expense'),0::bigint,'reservation does not create Expense');
select is((select count(*) from public.item_image_objects where id='expense-upload-one'),0::bigint,'reservation is not verified media');
select ok(not has_function_privilege('authenticated','public.spike_publish_verified_expense_attachment(uuid,text,text,bigint,text)','EXECUTE')
  and not has_function_privilege('anon','public.spike_publish_verified_expense_attachment(uuid,text,text,bigint,text)','EXECUTE'),
  'clients cannot claim they verified bytes');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(public.spike_read_expense_attachment_upload('expense-upload-one')->>'byte_count','12','verifier admission returns exact scoped claims');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_expense_attachment_upload('expense-upload-one')$$,
  '42501','expense_upload_unavailable','another principal cannot obtain verifier claims');
reset role;
set local role service_role;
select throws_ok($$select public.spike_publish_verified_expense_attachment('10000000-0000-0000-0000-000000000002','expense-upload-one',repeat('a',64),12,'application/pdf')$$,
  '42501','expense_upload_unavailable','verifier cannot substitute actor');
select throws_ok($$select public.spike_publish_verified_expense_attachment('10000000-0000-0000-0000-000000000001','expense-upload-one',repeat('b',64),12,'application/pdf')$$,
  'PT409','stored_bytes_mismatch','mismatching observation cannot publish');
select is(public.spike_publish_verified_expense_attachment('10000000-0000-0000-0000-000000000001','expense-upload-one',repeat('a',64),12,'application/pdf')->>'phase',
  'verified','trusted matching observation publishes media');
select is(public.spike_publish_verified_expense_attachment('10000000-0000-0000-0000-000000000001','expense-upload-one',repeat('a',64),12,'application/pdf')->>'expenseId',
  'pending-expense','verified retry retains Expense binding');
reset role;
select is((select count(*) from public.item_image_objects where id='expense-upload-one'),1::bigint,'verified retry creates one object');
select is((select count(*) from ledger_private.expense_receipt_attachments where attachment_id='expense-upload-one'),0::bigint,'publication does not invent an Expense reference');
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,
 final_amount_minor_units,currency,created_at,created_by_principal_id)
values('pending-expense','account-primary','expense-upload-project','category-furnishings','Vendor','2026-09-15',12,'USD',now(),'principal-owner');
insert into ledger_private.expense_receipt_attachments(account_id,expense_id,attachment_id,position)
values('account-primary','pending-expense','expense-upload-one',0);
update public.spike_account_memberships set financial_access='full' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.item_image_objects where id='expense-upload-one'),1::bigint,'another full financial member reads referenced object');
select set_config('storage.operation','storage.object.get_authenticated_info',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),1::bigint,'referenced Expense receipt metadata accessible');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),0::bigint,'Expense reference grants no bucket listing');
reset role;
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from public.item_image_objects where id='expense-upload-one'),0::bigint,'financial downgrade hides referenced object');
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),0::bigint,'financial downgrade hides referenced bytes');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select throws_ok($$select pg_temp.reserve_expense('expense-upload-one')$$,'42501','expense_upload_unavailable','removal rejects exact replay');
select is((select count(*) from storage.objects where name like '%/expense-upload-one/%'),0::bigint,'removal withdraws reserved byte access');
reset role;
set local role service_role;
select throws_ok($$select public.spike_publish_verified_expense_attachment('10000000-0000-0000-0000-000000000001','expense-upload-one',repeat('a',64),12,'application/pdf')$$,
  '42501','expense_upload_unavailable','verified retry does not bypass learned removal');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select pg_temp.reserve_expense('expense-upload-no-auth')$$,'28000','authentication_required','identity required');
reset role;
select * from finish();
rollback;
