-- The private command revalidates actor, active Account membership and every Item.
create function public.spike_edit_item_details(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.edit_item_details(p_command)
$$;
revoke all on function public.spike_edit_item_details(text) from public,anon,service_role;
grant execute on function public.spike_edit_item_details(text) to authenticated;
grant execute on function ledger_private.edit_item_details(text) to authenticated;
