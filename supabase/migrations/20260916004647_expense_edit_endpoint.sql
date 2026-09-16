create function public.spike_edit_expense(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.edit_expense(p_command)
$$;
revoke all on function public.spike_edit_expense(text) from public,anon,authenticated,service_role;
grant execute on function public.spike_edit_expense(text) to authenticated;
grant execute on function ledger_private.edit_expense(text) to authenticated;
