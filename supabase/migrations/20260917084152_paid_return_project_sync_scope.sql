-- Derived routing scope avoids one PowerSync parameter/bucket per paid charge.
-- Backfill under one transaction/table lock; frozen amounts and links do not change.
begin;
lock table ledger_private.paid_item_return_credits in access exclusive mode;
alter table ledger_private.paid_item_return_credits add column project_id text;
alter table ledger_private.paid_item_return_credits disable trigger paid_return_credit_evidence;
update ledger_private.paid_item_return_credits credit set project_id=charge.project_id
from ledger_private.item_charge_occurrences charge
where charge.account_id=credit.account_id and charge.id=credit.charge_id;
alter table ledger_private.paid_item_return_credits enable trigger paid_return_credit_evidence;
alter table ledger_private.paid_item_return_credits alter column project_id set not null;
alter table ledger_private.paid_item_return_credits add constraint paid_return_project_scope_fk
  foreign key(account_id,project_id) references public.spike_projects(account_id,id);
create index paid_return_project_scope_idx on ledger_private.paid_item_return_credits(account_id,project_id);

create function ledger_private.set_paid_return_project_scope() returns trigger
language plpgsql security invoker set search_path='' as $$
declare source_project text;
begin
  select project_id into strict source_project from ledger_private.item_charge_occurrences
    where account_id=new.account_id and id=new.charge_id;
  if new.project_id is not null and new.project_id<>source_project then
    raise sqlstate '23514' using message='Paid return Project must match its frozen charge';
  end if;
  new.project_id:=source_project;
  return new;
end;
$$;
revoke all on function ledger_private.set_paid_return_project_scope() from public,anon,authenticated,service_role;
create trigger paid_return_project_scope before insert on ledger_private.paid_item_return_credits
for each row execute function ledger_private.set_paid_return_project_scope();
commit;
