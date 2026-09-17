create function public.spike_edit_transaction_receipt_lines(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.edit_transaction_receipt_lines(p_command);
$$;
revoke all on function public.spike_edit_transaction_receipt_lines(text) from public,anon,authenticated,service_role;
grant execute on function public.spike_edit_transaction_receipt_lines(text) to authenticated;
grant execute on function ledger_private.edit_transaction_receipt_lines(text) to authenticated;
-- Authentication/current membership and financial visibility are checked inside
-- the private handler. No client receives table UPDATE privileges.
