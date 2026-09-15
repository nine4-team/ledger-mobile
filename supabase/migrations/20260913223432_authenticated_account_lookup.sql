-- One read-only, RLS-enforced snapshot for the sign-in -> Account picker handoff.
-- No caller-supplied identity, membership creation, or implicit selection.
create function public.spike_read_authenticated_accounts()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  principal text;
  accounts jsonb;
  membership_count bigint;
  account_count bigint;
begin
  if (select auth.uid()) is null
     or coalesce((select auth.jwt())->>'is_anonymous', 'false') <> 'false' then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select p.id into principal from public.spike_principals p
    where p.auth_user_id = (select auth.uid());
  if principal is null then
    -- An unmapped identity is not proof of an empty Account directory.
    raise exception using errcode = '42501', message = 'identity_not_linked';
  end if;

  select count(m.account_id), count(a.id),
    coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'displayName', a.display_name)
      order by a.id) filter (where a.id is not null), '[]'::jsonb)
    into membership_count, account_count, accounts
  from public.spike_account_memberships m
  left join public.spike_accounts a on a.id = m.account_id
  where m.principal_id = principal and m.state = 'active';

  if membership_count <> account_count then
    raise exception using errcode = '42501', message = 'account_directory_unavailable';
  end if;
  return jsonb_build_object('principalId', principal, 'accounts', accounts);
end;
$$;

revoke all on function public.spike_read_authenticated_accounts() from public, anon, service_role;
grant execute on function public.spike_read_authenticated_accounts() to authenticated;
