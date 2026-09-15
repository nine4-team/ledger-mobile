-- Financially authorized members can read canonical Expense receipts, including
-- historical receipts after Project archival. Pending uploads remain capturer-only.
create or replace function ledger_private.can_read_expense_receipt(p_account_id text,p_attachment_id text)
returns boolean language sql stable security definer set search_path='' as $$
  select (select auth.uid()) is not null and exists(
    select 1 from ledger_private.expense_receipt_attachments r
    join ledger_private.expenses e on e.account_id=r.account_id and e.id=r.expense_id
    join public.spike_account_memberships m on m.account_id=e.account_id
    join public.spike_principals actor on actor.id=m.principal_id
    where r.account_id=p_account_id and r.attachment_id=p_attachment_id
      and actor.auth_user_id=(select auth.uid()) and m.state='active' and m.financial_access='full'
  )
$$;
revoke all on function ledger_private.can_read_expense_receipt(text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.can_read_expense_receipt(text,text) to authenticated;
alter policy item_image_objects_reference_read on public.item_image_objects using(
  (select ledger_private.has_active_membership(account_id)) and (
    exists(select 1 from public.item_image_references r where r.account_id=item_image_objects.account_id and r.attachment_id=item_image_objects.id)
    or exists(select 1 from public.item_card_thumbnails t where t.account_id=item_image_objects.account_id and t.thumbnail_attachment_id=item_image_objects.id)
    or exists(select 1 from public.transaction_attachment_references r where r.account_id=item_image_objects.account_id and r.attachment_id=item_image_objects.id)
    or ledger_private.can_read_expense_receipt(account_id,id)
  )
);
-- Existing authenticated Storage get/info policy consults this object's RLS.
-- No listing, signing, overwrite or removal grant is added.
