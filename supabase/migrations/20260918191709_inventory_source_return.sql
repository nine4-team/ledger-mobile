-- Story 7 consumes proven immutable entry facts. No public acquisition writer,
-- historical backfill or price/tax allocation is authorized by this migration.
create table ledger_private.inventory_source_entries (
 id text primary key check(id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
 account_id text not null,
 item_id text not null,
 inventory_placement_id text not null,
 source_placement_id text not null,
 source_project_id text not null,
 source_category_id text not null,
 amount_minor_units bigint not null check(amount_minor_units>0),
 currency text not null check(currency ~ '^[A-Z]{3}$'),
 created_at timestamptz not null check(isfinite(created_at)),
 created_by_principal_id text not null references public.spike_principals(id),
 unique(account_id,id), unique(account_id,inventory_placement_id),
 foreign key(account_id,inventory_placement_id,item_id) references public.spike_item_placements(account_id,id,item_id),
 foreign key(account_id,source_placement_id,item_id,source_project_id) references public.spike_item_placements(account_id,id,item_id,project_id),
 foreign key(account_id,source_category_id) references public.spike_budget_categories(account_id,id)
);
create index inventory_source_entries_item on ledger_private.inventory_source_entries(account_id,item_id);
create index inventory_source_entries_source on ledger_private.inventory_source_entries(account_id,source_project_id,source_category_id);
create index inventory_source_entries_category on ledger_private.inventory_source_entries(account_id,source_category_id);
create index inventory_source_entries_creator on ledger_private.inventory_source_entries(created_by_principal_id);
alter table ledger_private.inventory_source_entries enable row level security;
alter table ledger_private.inventory_source_entries force row level security;
revoke all on ledger_private.inventory_source_entries from public,anon,authenticated,service_role;

create function ledger_private.guard_inventory_source_entry() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if tg_op<>'INSERT' then raise sqlstate '55000' using message='Inventory entry provenance is immutable'; end if;
 -- Structural proof is required even for trusted import/acquisition code. It
 -- does not establish a monetary basis by inspecting a mutable Item price.
 perform 1 from public.spike_item_placements p
 join public.spike_item_placements source on source.account_id=p.account_id and source.item_id=p.item_id
 where p.account_id=new.account_id and p.id=new.inventory_placement_id and p.item_id=new.item_id
   and p.scope_kind='business_inventory' and p.start_evidence='recorded_move'
   and source.id=new.source_placement_id and source.project_id=new.source_project_id
   and source.ended_at=p.started_at and source.ended_at=new.created_at
 for share of p,source;
 if not found then raise sqlstate '23514' using message='Exact recorded Project to Inventory transition required'; end if;
 return new;
end;
$$;
revoke all on function ledger_private.guard_inventory_source_entry() from public,anon,authenticated,service_role;
create trigger inventory_source_entry_guard before insert or update or delete on ledger_private.inventory_source_entries
 for each row execute function ledger_private.guard_inventory_source_entry();
create trigger inventory_source_entry_no_truncate before truncate on ledger_private.inventory_source_entries
 for each statement execute function ledger_private.guard_inventory_source_entry();

create table ledger_private.inventory_source_returns (
 account_id text not null, entry_id text not null, charge_id text not null,
 primary key(account_id,entry_id), unique(account_id,charge_id),
 foreign key(account_id,entry_id) references ledger_private.inventory_source_entries(account_id,id),
 foreign key(account_id,charge_id) references ledger_private.item_charge_occurrences(account_id,id)
);
alter table ledger_private.inventory_source_returns enable row level security;
alter table ledger_private.inventory_source_returns force row level security;
revoke all on ledger_private.inventory_source_returns from public,anon,authenticated,service_role;
create trigger inventory_source_return_guard before update or delete on ledger_private.inventory_source_returns
 for each row execute function ledger_private.guard_uninvoiced_item_return();
create trigger inventory_source_return_no_truncate before truncate on ledger_private.inventory_source_returns
 for each statement execute function ledger_private.guard_uninvoiced_item_return();
alter table ledger_private.item_charge_occurrences drop constraint item_charge_occurrences_price_basis_check;
alter table ledger_private.item_charge_occurrences add constraint item_charge_occurrences_price_basis_check
 check(price_basis in ('project_price','imported_invoice_amount','inventory_entry'));
alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price','edit_item_details','return_paid_items','assign_items_to_space','clear_item_space_assignments','edit_transaction_details','edit_transaction_receipt_lines','return_inventory_to_source'));

create function ledger_private.return_inventory_to_source(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
 selected jsonb; result public.spike_operation_results; failure text; client text;
 entry ledger_private.inventory_source_entries; placement public.spike_item_placements;
 received timestamptz; selected_currency text;
begin
 if current_setting('transaction_isolation')<>'read committed' then
   raise sqlstate '25001' using message='Source return requires READ COMMITTED'; end if;
 actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
 if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
   raise sqlstate '42501' using message='Authenticated actor required'; end if;
 perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor and state='active' for share;
 if not found then raise sqlstate '42501' using message='Active Account membership required'; end if;
 if jsonb_typeof(c) is distinct from 'object' or c->>'contractVersion' is distinct from 'return-inventory-to-source-v1'
   or not(c ?& array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','items'])
   or c-array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','items']<>'{}'::jsonb
   or exists(select 1 from jsonb_each(c-'items') where jsonb_typeof(value)<>'string')
   or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(operation)>128
   or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
   or jsonb_typeof(c->'items') is distinct from 'array' or jsonb_array_length(c->'items') not between 1 and 100 then
   raise sqlstate '22023' using message='Invalid source return command'; end if;
 fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(operation,0));
 select * into result from public.spike_operation_results where operation_id=operation;
 if found then
   if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
     is distinct from row(account,actor,'return_inventory_to_source'::text,fingerprint) then
     raise sqlstate '23505' using message='Operation identity conflict'; end if;
   return result;
 end if;
 received:=clock_timestamp();
 begin
   if (select count(distinct value->>'itemId') from jsonb_array_elements(c->'items'))<>jsonb_array_length(c->'items') then
     raise exception 'source_return_duplicate_item'; end if;
   select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId' and lifecycle='active' for share;
   if not found then raise exception 'source_return_destination_unavailable'; end if;
   perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
   if not found then raise exception 'source_return_destination_unavailable'; end if;
   for selected in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
     if jsonb_typeof(selected) is distinct from 'object'
       or not(selected ?& array['itemId','placementId','inventoryEntryId','projectPlacementId','occurrenceId'])
       or selected-array['itemId','placementId','inventoryEntryId','projectPlacementId','occurrenceId']<>'{}'::jsonb
       or exists(select 1 from jsonb_each(selected) where jsonb_typeof(value)<>'string'
         or value#>>'{}' !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value#>>'{}')>128) then
       raise exception 'source_return_item_invalid'; end if;
     perform 1 from public.spike_items where account_id=account and id=selected->>'itemId' for update;
     if not found then raise exception 'source_return_item_unavailable'; end if;
     select * into placement from public.spike_item_placements where account_id=account and item_id=selected->>'itemId'
       and id=selected->>'placementId' and scope_kind='business_inventory' and ended_at is null for update;
     if not found then raise exception 'source_return_placement_stale'; end if;
     select * into entry from ledger_private.inventory_source_entries where account_id=account and id=selected->>'inventoryEntryId'
       and item_id=placement.item_id and inventory_placement_id=placement.id and source_project_id=c->>'projectId';
     if not found then raise exception 'source_return_entry_unavailable'; end if;
     if selected_currency is not null and selected_currency<>entry.currency then
       raise exception 'source_return_entry_unavailable'; end if;
     selected_currency:=entry.currency;
     perform 1 from public.spike_budget_categories cat where cat.account_id=account and cat.id=entry.source_category_id
       and ledger_private.can_view_budget_category(cat.account_id,cat.visibility_class) for share;
     if not found then raise exception 'source_return_entry_unavailable'; end if;
     update public.spike_item_placements set ended_at=received,ended_by_principal_id=actor where id=placement.id;
     insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
       values(selected->>'projectPlacementId',account,entry.item_id,'project',entry.source_project_id,received,actor);
     insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
       amount_minor_units,currency,price_basis,created_at,created_by_principal_id)
       values(selected->>'occurrenceId',account,entry.source_project_id,entry.item_id,selected->>'projectPlacementId',
         entry.source_category_id,entry.amount_minor_units,entry.currency,'inventory_entry',received,actor);
     insert into ledger_private.inventory_source_returns(account_id,entry_id,charge_id)
       values(account,entry.id,selected->>'occurrenceId');
   end loop;
 exception when raise_exception then failure:=SQLERRM;
   when integrity_constraint_violation or numeric_value_out_of_range then failure:='source_return_integrity_conflict';
 end;
 insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
   command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
   completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
 values(operation,account,actor,'return_inventory_to_source','return-inventory-to-source-v1',fingerprint,fingerprint,c->>'projectId',
   case when failure is null then 'applied' else 'rejected' end,
   case when failure is null then 'inventory_items_returned_to_source' end,failure,
   to_timestamp((c->>'createdAtMs')::bigint/1000.0),received,received,(c->>'createdAtMs')::bigint,
   floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
 returning * into result;
 return result;
end;
$$;
revoke all on function ledger_private.return_inventory_to_source(text) from public,anon,service_role;
grant execute on function ledger_private.return_inventory_to_source(text) to authenticated;
create function public.spike_return_inventory_to_source(p_command text) returns public.spike_operation_results
language sql security invoker set search_path='' as $$ select ledger_private.return_inventory_to_source(p_command) $$;
revoke all on function public.spike_return_inventory_to_source(text) from public,anon,service_role;
grant execute on function public.spike_return_inventory_to_source(text) to authenticated;

create function public.spike_read_inventory_source_return_review(p_account_id text,p_item_ids text[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor text:=ledger_private.current_principal_id(); rows jsonb; source_count bigint; currency_count bigint;
begin
 if (select auth.uid()) is null or not exists(select 1 from public.spike_account_memberships
   where account_id=p_account_id and principal_id=actor and state='active') then
   raise sqlstate '42501' using message='Active Account membership required'; end if;
 if cardinality(p_item_ids) not between 1 and 100 or p_item_ids is null
   or (select count(distinct id) from unnest(p_item_ids) id)<>cardinality(p_item_ids) then
   raise sqlstate '22023' using message='Invalid source return selection'; end if;
 select jsonb_agg(jsonb_build_object('itemId',e.item_id,'placementId',e.inventory_placement_id,'inventoryEntryId',e.id,
   'sourceProjectId',e.source_project_id,'sourceCategoryId',e.source_category_id,
   'amountMinorUnits',e.amount_minor_units::text,'currency',e.currency) order by e.item_id collate "C"),count(distinct e.source_project_id),count(distinct e.currency)
 into rows,source_count,currency_count from ledger_private.inventory_source_entries e
 join public.spike_item_placements p on p.account_id=e.account_id and p.id=e.inventory_placement_id and p.ended_at is null
 join public.spike_projects project on project.account_id=e.account_id and project.id=e.source_project_id and project.lifecycle='active'
 join public.spike_clients client on client.account_id=project.account_id and client.id=project.client_id and client.lifecycle='active'
 join public.spike_budget_categories cat on cat.account_id=e.account_id and cat.id=e.source_category_id
 where e.account_id=p_account_id and e.item_id=any(p_item_ids)
   and ledger_private.can_view_budget_category(cat.account_id,cat.visibility_class);
 if rows is null or jsonb_array_length(rows)<>cardinality(p_item_ids) or source_count<>1 or currency_count<>1 then
   raise sqlstate '42501' using message='Source return evidence unavailable'; end if;
 return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',rows->0->>'sourceProjectId','items',rows);
end;
$$;
revoke all on function public.spike_read_inventory_source_return_review(text,text[]) from public,anon,service_role;
grant execute on function public.spike_read_inventory_source_return_review(text,text[]) to authenticated;
alter publication powersync add table ledger_private.inventory_source_entries;
