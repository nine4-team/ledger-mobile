-- Non-monetary download projection; accounting tables remain authoritative.
create table ledger_private.item_return_reviews (
 id text primary key,
 account_id text not null,
 project_id text not null,
 item_id text not null,
 placement_id text not null,
 category_id text not null,
 revision bigint not null,
 withdrawn boolean not null,
 has_live_invoice boolean not null,
 has_collected_invoice boolean not null,
 return_occurrence_id text,
 inventory_placement_id text,
 check((return_occurrence_id is null)=(inventory_placement_id is null)),
 foreign key(account_id,id) references ledger_private.item_charge_occurrences(account_id,id)
);
create index item_return_reviews_scope on ledger_private.item_return_reviews(account_id,project_id,category_id);
alter table ledger_private.item_return_reviews enable row level security;
alter table ledger_private.item_return_reviews force row level security;
revoke all on ledger_private.item_return_reviews from public,anon,authenticated,service_role;

create function ledger_private.refresh_item_return_review(account text,source text)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform ledger_private.lock_item_charge_source(account,source);
 insert into ledger_private.item_return_reviews(id,account_id,project_id,item_id,placement_id,category_id,revision,
   withdrawn,has_live_invoice,has_collected_invoice,return_occurrence_id,inventory_placement_id)
 select c.id,c.account_id,c.project_id,c.item_id,c.placement_id,c.category_id,c.revision,c.withdrawn_at is not null,
   exists(select 1 from ledger_private.live_invoice_memberships l where l.account_id=c.account_id
     and l.source_kind='item' and l.source_id=c.id and l.released_at is null),
   exists(select 1 from ledger_private.collected_invoice_lines l where l.account_id=c.account_id
     and l.source_kind='item' and l.source_id=c.id),r.id,r.inventory_placement_id
 from ledger_private.item_charge_occurrences c
 left join ledger_private.uninvoiced_item_returns r on r.account_id=c.account_id and r.charge_id=c.id
 where c.account_id=account and c.id=source
 on conflict(id) do update set category_id=excluded.category_id,revision=excluded.revision,
   withdrawn=excluded.withdrawn,has_live_invoice=excluded.has_live_invoice,
   has_collected_invoice=excluded.has_collected_invoice,return_occurrence_id=excluded.return_occurrence_id,
   inventory_placement_id=excluded.inventory_placement_id;
end;
$$;
create function ledger_private.item_return_review_changed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='item_charge_occurrences' then
   perform ledger_private.refresh_item_return_review(new.account_id,new.id);
 elsif tg_table_name='uninvoiced_item_returns' then
   perform ledger_private.refresh_item_return_review(new.account_id,new.charge_id);
 else
   if tg_op<>'INSERT' and old.source_kind='item' then
     perform ledger_private.refresh_item_return_review(old.account_id,old.source_id);
   end if;
   if tg_op<>'DELETE' and new.source_kind='item' and (tg_op='INSERT'
     or (new.account_id,new.source_kind,new.source_id) is distinct from (old.account_id,old.source_kind,old.source_id)) then
     perform ledger_private.refresh_item_return_review(new.account_id,new.source_id);
   end if;
 end if;
 return null;
end;
$$;
revoke all on function ledger_private.refresh_item_return_review(text,text),ledger_private.item_return_review_changed()
 from public,anon,authenticated,service_role;
create trigger item_return_charge_changed after insert or update on ledger_private.item_charge_occurrences
 for each row execute function ledger_private.item_return_review_changed();
create trigger item_return_live_changed after insert or update or delete on ledger_private.live_invoice_memberships
 for each row execute function ledger_private.item_return_review_changed();
create trigger item_return_collected_changed after insert on ledger_private.collected_invoice_lines
 for each row execute function ledger_private.item_return_review_changed();
create trigger item_return_fact_changed after insert on ledger_private.uninvoiced_item_returns
 for each row execute function ledger_private.item_return_review_changed();
do $$ declare c record; begin
 for c in select account_id,id from ledger_private.item_charge_occurrences order by account_id,id loop
   perform ledger_private.refresh_item_return_review(c.account_id,c.id);
 end loop;
end $$;

-- Bulk source removal is not an application command. Keep the derived table
-- coherent for authorized administrative truncation too; frozen sources already
-- reject TRUNCATE through their own guards.
create function ledger_private.item_return_live_truncated() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update ledger_private.item_return_reviews set has_live_invoice=false where has_live_invoice;
 return null;
end;
$$;
revoke all on function ledger_private.item_return_live_truncated() from public,anon,authenticated,service_role;
create trigger item_return_live_truncated after truncate on ledger_private.live_invoice_memberships
 for each statement execute function ledger_private.item_return_live_truncated();

-- Fresh environments provision the publication separately. Existing connected
-- environments must include this newly introduced replication source.
do $$ begin
 if exists(select 1 from pg_publication where pubname='powersync') then
   alter publication powersync add table ledger_private.item_return_reviews;
 end if;
end $$;
