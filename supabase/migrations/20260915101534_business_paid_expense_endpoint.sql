create function public.spike_create_expense(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.create_expense(p_command)
$$;
revoke all on function public.spike_create_expense(text) from public,anon,service_role;
grant execute on function public.spike_create_expense(text) to authenticated;
grant execute on function ledger_private.create_expense(text) to authenticated;
