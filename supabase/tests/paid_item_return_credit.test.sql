begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('paid-return-project','account-primary','client-existing','Paid return QA',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
select 'paid-return-item-'||v,'account-primary',v,'principal-owner' from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
select 'paid-return-original-'||v,'account-primary','paid-return-item-'||v,'business_inventory',
 '2024-01-01','principal-owner','2025-01-01','principal-owner' from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
select 'paid-return-project-'||v,'account-primary','paid-return-item-'||v,'project','paid-return-project',
 '2025-01-01','principal-owner' from unnest(array['a','b']) v;
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
select 'paid-return-charge-'||v,'account-primary','paid-return-project','paid-return-item-'||v,
 'paid-return-project-'||v,'category-furnishings',12345,'USD','2025-01-01','principal-owner' from unnest(array['a','b']) v;
select ledger_private.import_client_payment('paid-return-payment','account-primary','paid-return-project','client-existing',
 24690,'USD','synthetic-paid-return','paid-return-invoice','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values('paid-return-invoice','account-primary','paid-return-project','client-existing','paid-return-payment',1,'USD',24690);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
 source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
select 'paid-return-line-'||v,'account-primary','paid-return-invoice',case when v='a' then 0 else 1 end,'USD','item',
 'paid-return-charge-'||v,'paid-return-item-'||v,1,'category-furnishings',12345,'Paid Item','{}'
from unnest(array['a','b']) v;
update ledger_private.collected_invoices set sealed=true where id='paid-return-invoice';
create function pg_temp.paid_return_command(op text) returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'projectId','paid-return-project','contractVersion','return-paid-items-v1','createdAtMs','1788523200000',
 'items',(select jsonb_agg(jsonb_build_object('itemId','paid-return-item-'||v,'placementId','paid-return-project-'||v,
  'chargeId','paid-return-charge-'||v,'paidInvoiceLineId','paid-return-line-'||v,
  'inventoryPlacementId','paid-return-inventory-'||v,'returnOccurrenceId','paid-return-occurrence-'||v,
  'creditId','paid-return-credit-'||v) order by v) from unnest(array['a','b']) v))::text
$$;
create temp table original_lines as select * from ledger_private.collected_invoice_lines where invoice_id='paid-return-invoice';
create temp table original_payment as select * from public.spike_transactions where id='paid-return-payment';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select * from ledger_private.paid_item_return_credits$$,'42501',null,'No direct client credit table access');
select is(public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a'])#>>'{items,0,paidAmountMinorUnits}',
 '12345','Review returns exact frozen cents as decimal text');
select is(public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a'])#>>'{items,0,paidInvoiceLineId}',
 'paid-return-line-a','Review binds credit to original paid line');
select throws_ok($$select public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a','missing'])$$,
 '42501',null,'Review does not silently omit an unavailable Item');
select is((public.spike_return_paid_items(jsonb_set(pg_temp.paid_return_command('paid-return-bad-line')::jsonb,
 '{items,1,paidInvoiceLineId}','"paid-return-line-a"')::text)).error_code,
 'return_paid_basis_unavailable','Wrong frozen line rejects second Item');
reset role;
select is((select count(*) from ledger_private.paid_item_return_credits where project_id='paid-return-project'),0::bigint,'No first-Item credit survives rejected batch');
select is((select count(*) from public.spike_item_placements where project_id='paid-return-project' and ended_at is null),
 2::bigint,'Both placements survive rejected batch');
savepoint revoked_member;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_return_paid_items(pg_temp.paid_return_command('paid-return-revoked'))$$,
 '42501',null,'Removed member cannot return paid Items');
reset role;
rollback to revoked_member;
savepoint restricted_financial;
update public.spike_account_memberships set financial_access='limited'
 where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a'])$$,
 '42501',null,'Limited financial access cannot disclose frozen paid basis');
reset role;
update public.spike_account_memberships set financial_access='none'
 where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a'])$$,
 '42501',null,'No financial access cannot disclose frozen paid basis');
reset role;
rollback to restricted_financial;
set local role anon;
select throws_ok($$select public.spike_return_paid_items('{}')$$,'42501',null,'Anonymous return endpoint denied');
select throws_ok($$select public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a'])$$,
 '42501',null,'Anonymous review endpoint denied');
reset role;
set local role authenticated;
select throws_ok($$select public.spike_read_paid_return_review('account-other','paid-return-project',array['paid-return-item-a'])$$,
 '42501',null,'Foreign Account review cannot disclose paid basis');
select throws_ok($$select public.spike_read_paid_return_review('account-primary','missing-project',array['paid-return-item-a'])$$,
 '42501',null,'Paid Item identity does not bypass Project scope');
select throws_ok($$select public.spike_return_paid_items(jsonb_set(pg_temp.paid_return_command('paid-return-foreign')::jsonb,
 '{accountId}','"account-other"')::text)$$,'42501',null,'Foreign Account is denied before mutation');
reset role;
set local role authenticated;
select is((public.spike_return_paid_items(pg_temp.paid_return_command('paid-return-valid'))).phase,'applied','Authenticated paid return applies');
select throws_ok($$select public.spike_read_paid_return_review('account-primary','paid-return-project',array['paid-return-item-a'])$$,
 '42501',null,'Already returned Item cannot be reviewed as a new credit');
select is((public.spike_return_paid_items(pg_temp.paid_return_command('paid-return-valid'))).phase,'applied','Exact retry returns receipt');
select throws_ok($$select public.spike_return_paid_items(pg_temp.paid_return_command('paid-return-valid')||' ')$$,
 '23505',null,'Changed bytes cannot reuse operation identity');
select is((public.spike_return_paid_items(pg_temp.paid_return_command('paid-return-new-op'))).error_code,
 'return_placement_stale','A new operation cannot credit the same physical return twice');
reset role;
select is((select count(*) from ledger_private.paid_item_return_credits where project_id='paid-return-project'),2::bigint,'Exactly one credit per returned Item');
select is((select count(*) from ledger_private.paid_item_return_credits where project_id='paid-return-project'),
 2::bigint,'Credit Project routing is derived from the frozen charge');
select throws_ok($$insert into ledger_private.paid_item_return_credits
 (id,account_id,charge_id,paid_invoice_line_id,return_occurrence_id,inventory_placement_id,item_id,project_id)
 select id||'-wrong',account_id,charge_id,paid_invoice_line_id,return_occurrence_id,
 inventory_placement_id,item_id,'wrong-project' from ledger_private.paid_item_return_credits
 where item_id='paid-return-item-a'$$,'23514','Paid return Project must match its frozen charge',
 'Caller cannot redirect a credit into another Project stream');
select is((select count(*) from public.spike_item_placements where id like 'paid-return-inventory-%' and ended_at is null),
 2::bigint,'Same Items now in Inventory');
select is((select count(*) from ledger_private.item_charge_occurrences where id like 'paid-return-charge-%'
 and withdrawn_at is null and revision=1),2::bigint,'Frozen positive charges unchanged');
select results_eq('select to_jsonb(l)-''sync_is_current'' from ledger_private.collected_invoice_lines l where invoice_id=''paid-return-invoice'' order by id',
 'select to_jsonb(l)-''sync_is_current'' from original_lines l order by id','Frozen line amounts, category and membership unchanged');
select is((select count(*) from ledger_private.collected_invoice_lines where invoice_id='paid-return-invoice' and not sync_is_current),
 2::bigint,'Derived current-placement routing changes; frozen historical contents remain');
select results_eq('select * from public.spike_transactions where id=''paid-return-payment''',
 'select * from original_payment','Original cash payment unchanged');
select is((select sum(-l.signed_amount_minor_units) from ledger_private.paid_item_return_credits c
 join ledger_private.collected_invoice_lines l on l.id=c.paid_invoice_line_id
 where c.project_id='paid-return-project'),-24690::numeric,'Credit basis is exact frozen negative amount');
select throws_ok($$update ledger_private.paid_item_return_credits set charge_id='changed' where project_id='paid-return-project'$$,'55000',null,'Return evidence immutable');
select throws_ok($$truncate ledger_private.paid_item_return_credits$$,'55000',null,'Cannot truncate return evidence');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.spike_return_paid_items(pg_temp.paid_return_command('paid-return-forged'))$$,
 '42501',null,'Different principal cannot impersonate recorded actor');
reset role;
-- A paid line does not itself prove that an imported Item was sold from Inventory.
insert into public.spike_items(id,account_id,description,created_by_principal_id)
 values('unproven-paid-item','account-primary','Imported observation','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id,start_evidence)
 values('unproven-paid-placement','account-primary','unproven-paid-item','project','paid-return-project','2025-01-01','principal-owner','import_observation');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_at,created_by_principal_id)
 values('unproven-paid-charge','account-primary','paid-return-project','unproven-paid-item','unproven-paid-placement','category-furnishings',100,'USD','2025-01-01','principal-owner');
select ledger_private.import_client_payment('unproven-paid-payment','account-primary','paid-return-project','client-existing',
 100,'USD','synthetic-unproven','unproven-paid-invoice','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
 values('unproven-paid-invoice','account-primary','paid-return-project','client-existing','unproven-paid-payment',1,'USD',100);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
 values('unproven-paid-line','account-primary','unproven-paid-invoice',0,'USD','item','unproven-paid-charge','unproven-paid-item',1,'category-furnishings',100,'Observed paid Item','{}');
update ledger_private.collected_invoices set sealed=true where id='unproven-paid-invoice';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.spike_read_paid_return_review('account-primary','paid-return-project',array['unproven-paid-item'])$$,
 '42501',null,'Imported placement observation cannot invent an Inventory sale');
select is((public.spike_return_paid_items(jsonb_set(pg_temp.paid_return_command('unproven-paid-return')::jsonb,'{items}',
 '[{"itemId":"unproven-paid-item","placementId":"unproven-paid-placement","chargeId":"unproven-paid-charge","paidInvoiceLineId":"unproven-paid-line","inventoryPlacementId":"unproven-successor","returnOccurrenceId":"unproven-return","creditId":"unproven-credit"}]'::jsonb)::text)).error_code,
 'return_origin_unproven','Bypassing review still cannot return an unproven imported sale');
reset role;
select is((select count(*) from ledger_private.paid_item_return_credits where item_id='unproven-paid-item'),0::bigint,
 'No fabricated credit is persisted');
select is((select count(*) from public.spike_item_placements where item_id='unproven-paid-item' and ended_at is null and scope_kind='project'),1::bigint,
 'Rejected imported return preserves physical placement');
select * from finish();
rollback;
