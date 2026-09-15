-- Same narrow wrapper pattern as category commands. The private handler
-- independently checks authenticated principal and active Account membership.
create function public.spike_sell_inventory_items(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.sell_inventory_items(p_command)
$$;
revoke all on function public.spike_sell_inventory_items(text) from public,anon,service_role;
grant execute on function public.spike_sell_inventory_items(text) to authenticated;
grant execute on function ledger_private.sell_inventory_items(text) to authenticated;
