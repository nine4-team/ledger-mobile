-- Narrow authenticated read; no direct table grants or mutation authority.
create function ledger_private.read_expense(p_account_id text,p_project_id text,p_expense_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;
begin
  if (select auth.uid()) is null then
    raise exception using errcode='42501',message='expense_not_available';
  end if;
  select jsonb_build_object(
    'accountId',e.account_id,'projectId',e.project_id,'expenseId',e.id,
    'vendor',e.vendor,'date',to_char(e.expense_date,'YYYY-MM-DD'),
    'amountMinorUnits',e.final_amount_minor_units::text,'currency',e.currency,
    'categoryId',e.category_id,'notes',e.notes,'revision',e.revision::text,
    'receiptLines',coalesce((select jsonb_agg(jsonb_build_object(
      'id',l.id,'description',l.description,'magnitudeMinorUnits',l.magnitude_minor_units::text,
      'currency',l.currency,'effect',l.effect,'quantity',l.quantity::text) order by l.position)
      from ledger_private.expense_receipt_lines l where l.account_id=e.account_id and l.expense_id=e.id),'[]'::jsonb),
    'receiptAttachmentIds',coalesce((select jsonb_agg(a.attachment_id order by a.position)
      from ledger_private.expense_receipt_attachments a where a.account_id=e.account_id and a.expense_id=e.id),'[]'::jsonb)
  ) into payload
  from ledger_private.expenses e
  join public.spike_account_memberships m on m.account_id=e.account_id
    and m.principal_id=ledger_private.current_principal_id() and m.state='active' and m.financial_access='full'
  where e.account_id=p_account_id and e.project_id=p_project_id and e.id=p_expense_id;
  if payload is null then
    raise exception using errcode='42501',message='expense_not_available';
  end if;
  return payload;
end;
$$;
revoke all on function ledger_private.read_expense(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_expense(text,text,text) to authenticated;
create function public.spike_read_expense(p_account_id text,p_project_id text,p_expense_id text)
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_expense(p_account_id,p_project_id,p_expense_id)
$$;
revoke all on function public.spike_read_expense(text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_expense(text,text,text) to authenticated;
