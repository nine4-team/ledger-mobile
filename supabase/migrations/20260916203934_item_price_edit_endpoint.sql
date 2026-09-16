-- Business authorization stays in the scoped private command. No table writes.
create function public.spike_edit_uncollected_item_price(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.edit_uncollected_item_price(p_command)
$$;
revoke all on function public.spike_edit_uncollected_item_price(text) from public,anon,service_role;
grant execute on function public.spike_edit_uncollected_item_price(text) to authenticated;
grant execute on function ledger_private.edit_uncollected_item_price(text) to authenticated;
