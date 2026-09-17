begin;
select no_plan();
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id,
 source,notes,payment_method,has_email_receipt,transaction_date,non_item_receipt_lines)
values('edit-details','account-primary',9007199254740993,'USD','return','vendor_payment','business_inventory','category-system',
 'Original vendor',E'  Raw\nnotes  ','Original method',null,'2024-02-29',
 '[{"id":"tax","description":"Tax","amountMinorUnits":"100","effect":"increase"}]');
create temp table details_before as select to_jsonb(t)-array['source','notes','payment_method','has_email_receipt','details_revision'] as value
 from public.spike_transactions t where id='edit-details';
create function pg_temp.details_command(op text, changes jsonb, revision text default '1')
returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-restricted',
 'contractVersion','transaction-details-edit-v1','createdAtMs','1000','transactionId','edit-details',
 'scopeKind','business_inventory','projectId',null,'clientId',null,'expectedRevision',revision,'changes',changes)::text;
$$;
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-first',
 '{"source":null,"hasEmailReceipt":false}'))).phase,'applied','Ordinary member may edit visible descriptive details');
select is((select source from public.spike_transactions where id='edit-details'),null::text,'Explicit clear is applied');
select is((select has_email_receipt from public.spike_transactions where id='edit-details'),false,'Unknown may be explicitly answered no');
select is((select notes from public.spike_transactions where id='edit-details'),E'  Raw\nnotes  ','Omitted text preserved verbatim');
select is((select details_revision from public.spike_transactions where id='edit-details'),2::bigint,'One descriptive revision');
set local role authenticated;
select is(public.spike_read_transaction_detail('account-primary','edit-details')->>'detailsRevision','2','Detail read exposes authoritative descriptive revision');
select is((select value->>'detailsRevision' from jsonb_array_elements(
 public.spike_read_transaction_list('account-primary','business_inventory')->'transactions') where value->>'transactionId'='edit-details'),
 '2','List and detail share the same edit revision');
reset role;
select is((select to_jsonb(t)-array['source','notes','payment_method','has_email_receipt','details_revision']
 from public.spike_transactions t where id='edit-details'),(select value from details_before),'All non-descriptive evidence unchanged');
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-first',
 '{"source":null,"hasEmailReceipt":false}'))).phase,'applied','Identical retry returns original result');
select is((select details_revision from public.spike_transactions where id='edit-details'),2::bigint,'Retry does not apply twice');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-first','{"notes":"changed"}'))$$,
 '23505','Operation identity conflict','Different retry cannot reuse accepted identity');
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-stale','{"notes":"stale"}'))).error_code,
 'transaction_edit_stale','Stale edits reject durably');
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-stale','{"notes":"stale"}'))).phase,
 'rejected','Rejected retry remains rejected');
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-noop','{"source":null}','2'))).phase,
 'applied','Same-value explicit edit is idempotent');
select is((select details_revision from public.spike_transactions where id='edit-details'),2::bigint,'No-op does not manufacture revision');
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-text','{"notes":"  New 🪑  ","paymentMethod":""}','2'))).phase,
 'applied','Raw Unicode and empty text supported');
select is((select notes from public.spike_transactions where id='edit-details'),'  New 🪑  ','Whitespace retained');
select is((select payment_method from public.spike_transactions where id='edit-details'),'','Empty value differs from null');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-money','{"amountMinorUnits":"0"}','3'))$$,
 '22023','Invalid Transaction edit command','Financial fields cannot be written');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-empty','{}','3'))$$,
 '22023','Invalid Transaction edit command','Empty changes rejected');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-email','{"hasEmailReceipt":null}','3'))$$,
 '22023','Invalid Transaction field changes','Null is not an email-receipt answer');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-number','{"notes":42}','3'))$$,
 '22023','Invalid Transaction field changes','Non-text notes rejected');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-revision','{"notes":"bad"}','0'))$$,
 '22023','Invalid Transaction edit command','Invalid revision rejected');
select throws_ok($$select ledger_private.edit_transaction_details((pg_temp.details_command('details-actor','{"notes":"bad"}','3')::jsonb
 || '{"actorPrincipalId":"principal-owner"}')::text)$$,'42501','Authenticated actor required','Actor spoofing rejected');
select throws_ok($$select ledger_private.edit_transaction_details((pg_temp.details_command('details-scope','{"notes":"bad"}','3')::jsonb
 || '{"scopeKind":"project","projectId":"wrong","clientId":"wrong"}')::text)$$,
 '42501','Transaction edit unavailable','Wrong scope denied');
select throws_ok($$select ledger_private.edit_transaction_details((pg_temp.details_command('details-other','{"notes":"bad"}','3')::jsonb
 || '{"accountId":"account-other"}')::text)$$,'42501','Transaction edit access required','Other tenant denied');

insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values('details-fee','account-primary','Details Fee','fee','company_financial',60,'active',false,false,1,1);
update public.spike_transactions set category_id='details-fee' where id='edit-details';
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-hidden','{"notes":"bad"}','3'))$$,
 '42501','Transaction edit unavailable','Hidden Fee denies ordinary member');
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-first','{"source":null,"hasEmailReceipt":false}'))$$,
 '42501','Transaction edit unavailable','Replay rechecks current financial visibility');
update public.spike_budget_categories set kind='general',revision=revision+1 where id='details-fee';
select is((ledger_private.edit_transaction_details(pg_temp.details_command('details-general','{"notes":"Visible again"}','3'))).phase,
 'applied','General visibility naturally restores member editing');

insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('details-project','account-primary','client-existing','Details project',now(),now(),1,1,'principal-owner');
select ledger_private.import_client_payment('details-paid','account-primary','details-project','client-existing',100,'USD',
 'synthetic-details','paid','\x01'::bytea);
create temp table paid_before as select to_jsonb(t) as value from public.spike_transactions t where id='details-paid';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select throws_ok($$select ledger_private.edit_transaction_details((pg_temp.details_command('details-paid-edit','{"notes":"bad"}')::jsonb
 || '{"actorPrincipalId":"principal-owner","transactionId":"details-paid","scopeKind":"project","projectId":"details-project","clientId":"client-existing"}')::text)$$,
 '42501','Transaction edit unavailable','Even owner cannot edit immutable imported payment through descriptive writer');
select is((select to_jsonb(t) from public.spike_transactions t where id='details-paid'),(select value from paid_before),'Imported payment unchanged');
select throws_ok($$update public.spike_transactions set notes='bad' where id='details-paid'$$,
 '55000','Imported payment evidence is immutable; correction requires an explicit accounting workflow','Original immutable trigger still enforced');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-first','{"source":null,"hasEmailReceipt":false}'))$$,
 '42501','Transaction edit access required','Removed member cannot replay');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_transaction_details(pg_temp.details_command('details-anon','{"notes":"bad"}','4'))$$,
 '42501','Authenticated actor required','Anonymous actor denied');
select ok(has_function_privilege('authenticated','public.spike_edit_transaction_details(text)','execute'),'Authenticated command endpoint available');
select ok(not has_function_privilege('anon','public.spike_edit_transaction_details(text)','execute'),'Anonymous endpoint denied');
select ok(not has_function_privilege('service_role','public.spike_edit_transaction_details(text)','execute'),'Service-role endpoint denied');
select ok(not has_function_privilege('anon','ledger_private.edit_transaction_details(text)','execute'),'Anonymous execution denied');
select ok(not has_function_privilege('service_role','ledger_private.edit_transaction_details(text)','execute'),'Service bypass not granted');
select ok(not has_any_column_privilege('authenticated','public.spike_transactions','UPDATE'),'No direct Transaction writer granted');
update public.spike_account_memberships set state='active' where account_id='account-primary' and principal_id='principal-restricted';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select is((public.spike_edit_transaction_details(pg_temp.details_command('details-endpoint','{"notes":"Endpoint edit"}','4'))).phase,
 'applied','Actual endpoint preserves ordinary-member edit permission');
select is(public.spike_read_transaction_detail('account-primary','edit-details')->>'notes','Endpoint edit','Endpoint edit readback');
reset role;
select * from finish();
rollback;
