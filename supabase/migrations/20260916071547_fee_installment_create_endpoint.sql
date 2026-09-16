create function public.spike_create_fee_installment(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.create_fee_installment(p_command)
$$;
revoke all on function public.spike_create_fee_installment(text) from public,anon,authenticated,service_role;
grant execute on function public.spike_create_fee_installment(text) to authenticated;
grant execute on function ledger_private.create_fee_installment(text) to authenticated;
