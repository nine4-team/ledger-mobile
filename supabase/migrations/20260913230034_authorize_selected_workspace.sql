-- Selection is local intent; this separate, read-only check authorizes the
-- chosen workspace against current membership. It grants no new membership.
create function public.spike_authorize_workspace(p_account_id text)
returns jsonb
language plpgsql stable security invoker set search_path = ''
as $$
declare
  principal text;
  access jsonb;
begin
  if (select auth.uid()) is null
     or coalesce((select auth.jwt())->>'is_anonymous', 'false') <> 'false' then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select id into principal from public.spike_principals
    where auth_user_id = (select auth.uid());
  if principal is null then
    raise exception using errcode = '42501', message = 'identity_not_linked';
  end if;
  select jsonb_build_object('principalId', principal, 'accountId', a.id,
      'role', m.role, 'financialAccess', m.financial_access)
    into access
  from public.spike_account_memberships m
  join public.spike_accounts a on a.id = m.account_id
  where m.principal_id = principal and m.account_id = p_account_id
    and m.state = 'active';
  if access is null then
    -- Nonexistent, foreign and removed Accounts have the same result.
    raise exception using errcode = '42501', message = 'workspace_access_denied';
  end if;
  return access;
end;
$$;
revoke all on function public.spike_authorize_workspace(text) from public, anon, service_role;
grant execute on function public.spike_authorize_workspace(text) to authenticated;
