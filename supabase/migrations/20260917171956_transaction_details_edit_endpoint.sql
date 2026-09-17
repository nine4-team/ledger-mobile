-- The internal handler rechecks current actor, membership, exact Transaction
-- scope, category visibility and immutable-payment boundary on every request.
create function public.spike_edit_transaction_details(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.edit_transaction_details(p_command)
$$;
revoke all on function public.spike_edit_transaction_details(text) from public,anon,service_role;
grant execute on function public.spike_edit_transaction_details(text) to authenticated;
grant execute on function ledger_private.edit_transaction_details(text) to authenticated;
