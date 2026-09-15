-- D-030: category definitions remain stable identities. Commands never rewrite
-- Items, Transactions, paid Invoice snapshots or payment amounts.
-- Swift String equality treats canonically equivalent spellings as equal.
-- Preserve display bytes; normalize only the case-insensitive uniqueness key.
drop index public.spike_budget_categories_account_name_idx;
create unique index spike_budget_categories_account_name_idx
  on public.spike_budget_categories (account_id, (normalize(lower(display_name), NFC) collate "C"));

alter table public.spike_operation_results
  drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results
  add constraint spike_operation_results_command_type_check check (command_type in
    ('create_client', 'create_project', 'archive_project', 'archive_client',
     'revise_space_checklists', 'manage_categories'));

alter table public.spike_operation_results
  add constraint spike_operation_results_category_namespace_check check (
    (command_type = 'manage_categories'
      and operation_id ~ '^category-management-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and substring(operation_id from 21 for 64) = encode(
        extensions.digest(convert_to(account_id, 'UTF8'), 'sha256'), 'hex'))
    or (command_type <> 'manage_categories' and operation_id !~ '^category-management-'));

-- Permit a single UPDATE to swap occupied order positions. It remains unique
-- at statement completion; we do not expose a partial per-row reorder.
alter table public.spike_budget_categories
  drop constraint spike_budget_categories_account_id_presentation_order_key;
alter table public.spike_budget_categories
  add constraint spike_budget_categories_account_id_presentation_order_key
  unique (account_id, presentation_order) deferrable initially immediate;

-- Keep the existing projection column for current readers, but derive it from
-- current kind for EVERY write. There is no previous-Fee or transition state.
create function ledger_private.derive_category_visibility()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.visibility_class := case when new.kind = 'fee' then 'company_financial' else 'ordinary' end;
  return new;
end
$$;
revoke all on function ledger_private.derive_category_visibility()
  from public, anon, authenticated, service_role;
create trigger derive_category_visibility
before insert or update on public.spike_budget_categories
for each row execute function ledger_private.derive_category_visibility();
update public.spike_budget_categories
set visibility_class = case when kind = 'fee' then 'company_financial' else 'ordinary' end
where visibility_class <> case when kind = 'fee' then 'company_financial' else 'ordinary' end;

create or replace function ledger_private.spike_manage_categories(p_envelope_json text)
returns public.spike_operation_results
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb;
  p jsonb;
  a text;
  actor text;
  operation text;
  fingerprint text;
  action text;
  category text;
  member public.spike_account_memberships%rowtype;
  existing public.spike_operation_results%rowtype;
  result public.spike_operation_results%rowtype;
  current_row public.spike_budget_categories%rowtype;
  error_code text;
  name text;
  expected bigint;
  position bigint;
  entry jsonb;
  definition_keys text[] := array['action','categoryId','name','kind','excludesFromOverallBudget'];
  received timestamptz := date_trunc('milliseconds', clock_timestamp());
  completed timestamptz;
  captured_ms bigint;
  captured timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;
  if p_envelope_json is null or octet_length(p_envelope_json) > 262144 then
    raise exception using errcode = '22023', message = 'category command invalid';
  end if;
  e := p_envelope_json::jsonb;
  a := e->>'accountId';
  actor := e->>'actorPrincipalId';
  if actor is distinct from (select ledger_private.current_principal_id()) then
    raise exception using errcode = '42501', message = 'actor is not the authenticated principal';
  end if;
  -- Hold current membership while applying the command: access removal cannot
  -- commit between authorization and the writes. No role escalation for presets.
  select * into member from public.spike_account_memberships m
    where m.account_id = a and m.principal_id = actor and m.state = 'active'
    for share;
  if not found then
    raise exception using errcode = '42501', message = 'active account membership required';
  end if;
  if not ledger_private.jsonb_has_exact_keys(e,
      array['accountId','actorPrincipalId','clientCreatedAt','contractVersion','operationId','payload','preconditions'])
    or jsonb_typeof(e->'accountId') is distinct from 'string'
    or jsonb_typeof(e->'actorPrincipalId') is distinct from 'string'
    or jsonb_typeof(e->'operationId') is distinct from 'string'
    or jsonb_typeof(e->'contractVersion') is distinct from 'string'
    or e->>'contractVersion' is distinct from 'category-management-v1'
    or e->'preconditions' is distinct from '[]'::jsonb
    or jsonb_typeof(e->'clientCreatedAt') is distinct from 'number'
    or (e->>'clientCreatedAt') !~ '^-?[0-9]{1,15}$'
    or jsonb_typeof(e->'payload') is distinct from 'object' then
    raise exception using errcode = '22023', message = 'category command invalid';
  end if;
  operation := e->>'operationId';
  if operation is null or operation !~ '^category-management-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or substring(operation from 21 for 64) is distinct from encode(
      extensions.digest(convert_to(a, 'UTF8'), 'sha256'), 'hex') then
    raise exception using errcode = '22023', message = 'category operation identity invalid';
  end if;
  captured_ms := (e->>'clientCreatedAt')::bigint;
  captured := to_timestamp(captured_ms::double precision / 1000);
  fingerprint := encode(extensions.digest(convert_to(p_envelope_json, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation, 0));
  select * into existing from public.spike_operation_results r where r.operation_id = operation;
  if found then
    if existing.account_id <> a or existing.actor_principal_id <> actor
      or existing.command_type <> 'manage_categories'
      or existing.envelope_sha256 <> fingerprint then
      raise exception using errcode = '22023', message = 'operation identity already used';
    end if;
    return existing;
  end if;
  -- One Account category set lock serializes creation, names and full ordering.
  -- Row locks are stable-ID ordered to cooperate with other reference consumers.
  perform pg_advisory_xact_lock(hashtextextended('category-set:' || a, 0));
  perform 1 from public.spike_budget_categories c where c.account_id = a order by c.id for update;
  p := e->'payload';
  action := p->>'action';
  category := p->>'categoryId';
  if action in ('create','edit') then
    if not ledger_private.jsonb_has_exact_keys(p, definition_keys ||
      case when action = 'edit' then array['expectedRevision'] else array[]::text[] end)
      or jsonb_typeof(p->'name') is distinct from 'string'
      or jsonb_typeof(p->'kind') is distinct from 'string'
      or p->>'kind' not in ('general','itemized','fee')
      or jsonb_typeof(p->'excludesFromOverallBudget') is distinct from 'boolean' then
      error_code := 'category_payload_invalid';
    end if;
    name := p->>'name';
    -- The shared form/MCP/database count at most100 Unicode code points.
    -- Wire names are already trimmed by the shared form/MCP. Reject untrimmed
    -- envelopes rather than rewriting bytes covered by their operation hash.
    -- Whitespace matches Foundation's whitespacesAndNewlines (including U+200B).
    -- Explicit Unicode Cc/Cf ranges avoid locale-dependent POSIX cntrl behavior.
    if name is null or name = '' or char_length(name) > 100
      or name <> btrim(name, U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\200B\2028\2029\202F\205F\3000')
      or name ~ U&'[\0001-\001F\007F-\009F\00AD\0600-\0605\061C\06DD\070F\0890-\0891\08E2\180E\200B-\200F\202A-\202E\2060-\2064\2066-\206F\FEFF\FFF9-\FFFB\+0110BD\+0110CD\+013430-\+01343F\+01BCA0-\+01BCA3\+01D173-\+01D17A\+0E0001\+0E0020-\+0E007F]'
      then error_code := 'category_name_invalid'; end if;
    if p->>'kind' = 'fee' and member.financial_access <> 'full' then
      error_code := 'category_unavailable';
    end if;
  elsif action in ('archive','restore') then
    if not ledger_private.jsonb_has_exact_keys(p,array['action','categoryId','expectedRevision']) then
      error_code := 'category_payload_invalid';
    end if;
  elsif action = 'reorder' then
    if not ledger_private.jsonb_has_exact_keys(p,array['action','order'])
      or jsonb_typeof(p->'order') is distinct from 'array' then
      error_code := 'category_order_invalid';
    elsif jsonb_array_length(p->'order') = 0 then
      error_code := 'category_order_invalid';
    end if;
  else
    error_code := 'category_payload_invalid';
  end if;
  if action <> 'reorder' and (category is null
    or jsonb_typeof(p->'categoryId') is distinct from 'string'
    or category !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$') then
    error_code := 'category_payload_invalid';
  end if;
  if error_code is null and action in ('edit','archive','restore') then
    if jsonb_typeof(p->'expectedRevision') is distinct from 'string'
      or (p->>'expectedRevision') !~ '^[1-9][0-9]{0,18}$'
      or (p->>'expectedRevision')::numeric >= 9223372036854775807 then
      error_code := 'category_payload_invalid';
    else expected := (p->>'expectedRevision')::bigint; end if;
    select * into current_row from public.spike_budget_categories c
      where c.account_id = a and c.id = category
      and (c.kind <> 'fee' or member.financial_access = 'full');
    if not found then error_code := 'category_unavailable';
    elsif current_row.is_system then error_code := 'category_protected';
    elsif error_code is null and current_row.revision <> expected then
      error_code := 'category_revision_conflict';
    end if;
  end if;
  if error_code is null and action in ('create','edit') and exists (
    select 1 from public.spike_budget_categories c where c.account_id = a
      and c.id <> category
      and (normalize(lower(c.display_name), NFC) collate "C") = (normalize(lower(name), NFC) collate "C")
  ) then error_code := 'category_name_unavailable'; end if;
  if error_code is null and action = 'create' then
    if exists (select 1 from public.spike_budget_categories c where c.id = category) then
      error_code := 'category_unavailable';
    else
      select coalesce(max(c.presentation_order) + 1,0) into position
        from public.spike_budget_categories c where c.account_id = a;
      if position > 4294967295 then error_code := 'category_order_invalid'; end if;
    end if;
  end if;
  if error_code is null and action = 'reorder' then
    for entry in select value from jsonb_array_elements(p->'order') loop
      if not ledger_private.jsonb_has_exact_keys(entry,array['categoryId','expectedRevision'])
        or jsonb_typeof(entry->'categoryId') is distinct from 'string'
        or jsonb_typeof(entry->'expectedRevision') is distinct from 'string'
        or (entry->>'expectedRevision') !~ '^[1-9][0-9]{0,18}$'
        or (entry->>'expectedRevision')::numeric >= 9223372036854775807 then
        error_code := 'category_order_invalid'; exit;
      end if;
    end loop;
    if error_code is null and (
      (select count(*) from jsonb_array_elements(p->'order')) <>
      (select count(distinct value->>'categoryId') from jsonb_array_elements(p->'order'))
      or (select array_agg(value->>'categoryId' order by value->>'categoryId') from jsonb_array_elements(p->'order'))
        is distinct from (select array_agg(c.id order by c.id) from public.spike_budget_categories c
          where c.account_id = a and c.lifecycle = 'active' and not c.is_system
          and (c.kind <> 'fee' or member.financial_access = 'full'))
    ) then error_code := 'category_order_invalid'; end if;
    if error_code is null and exists (
      select 1 from jsonb_array_elements(p->'order') e
      join public.spike_budget_categories c on c.account_id = a and c.id = e.value->>'categoryId'
      where c.revision <> (e.value->>'expectedRevision')::bigint
    ) then error_code := 'category_revision_conflict'; end if;
  end if;

  completed := greatest(received, date_trunc('milliseconds', clock_timestamp()));
  if error_code is null then
    if action = 'create' then
      insert into public.spike_budget_categories(id,account_id,display_name,kind,
        excludes_from_overall_budget,presentation_order,created_at,updated_at,created_at_ms,updated_at_ms)
      values(category,a,name,p->>'kind',(p->>'excludesFromOverallBudget')::boolean,
        position,completed,completed,(extract(epoch from completed)*1000)::bigint,
        (extract(epoch from completed)*1000)::bigint);
    elsif action = 'reorder' then
      with slots as (
        select c.presentation_order,row_number() over(order by c.presentation_order) as ordinal
        from public.spike_budget_categories c where c.account_id = a and c.lifecycle = 'active'
          and not c.is_system and (c.kind <> 'fee' or member.financial_access = 'full')
      ), desired as (
        select e.value->>'categoryId' as id,s.presentation_order
        from jsonb_array_elements(p->'order') with ordinality e(value,ordinal)
        join slots s using(ordinal)
      )
      update public.spike_budget_categories c set presentation_order = d.presentation_order,
        revision = c.revision + 1,updated_at = greatest(c.updated_at,completed),
        updated_at_ms = greatest(c.updated_at_ms,(extract(epoch from completed)*1000)::bigint)
      from desired d where c.account_id = a and c.id = d.id and c.presentation_order <> d.presentation_order;
    else
      update public.spike_budget_categories c set
        display_name = coalesce(name,c.display_name),kind = coalesce(p->>'kind',c.kind),
        excludes_from_overall_budget = coalesce((p->>'excludesFromOverallBudget')::boolean,c.excludes_from_overall_budget),
        lifecycle = case action when 'archive' then 'archived' when 'restore' then 'active' else c.lifecycle end,
        revision = c.revision + 1,updated_at = greatest(c.updated_at,completed),
        updated_at_ms = greatest(c.updated_at_ms,(extract(epoch from completed)*1000)::bigint)
      where c.account_id = a and c.id = category and
        (c.display_name is distinct from coalesce(name,c.display_name)
        or c.kind is distinct from coalesce(p->>'kind',c.kind)
        or c.excludes_from_overall_budget is distinct from coalesce((p->>'excludesFromOverallBudget')::boolean,c.excludes_from_overall_budget)
        or c.lifecycle <> case action when 'archive' then 'archived' when 'restore' then 'active' else c.lifecycle end);
    end if;
  end if;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,
    command_type,contract_version,command_fingerprint,envelope_sha256,subject_id,
    phase,result_code,error_code,client_created_at,server_received_at,completed_at,
    client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,a,actor,'manage_categories','category-management-v1',fingerprint,fingerprint,
    -- Results are Account-wide reads. Identify the category set, not a possibly
    -- hidden Fee category; private command payloads remain on the owning device.
    a,case when error_code is null then 'applied' else 'rejected' end,
    case when error_code is null then 'categories_updated' end,error_code,captured,received,completed,
    captured_ms,(extract(epoch from received)*1000)::bigint,(extract(epoch from completed)*1000)::bigint)
  returning * into result;
  return result;
end
$$;
revoke all on function ledger_private.spike_manage_categories(text) from public, anon, service_role;
grant execute on function ledger_private.spike_manage_categories(text) to authenticated;
create or replace function public.spike_manage_categories(p_envelope_json text)
returns public.spike_operation_results language sql security invoker set search_path = '' as $$
  select ledger_private.spike_manage_categories(p_envelope_json)
$$;
revoke all on function public.spike_manage_categories(text) from public, anon, service_role;
grant execute on function public.spike_manage_categories(text) to authenticated;

-- MCP category directory: the same authorized definitions as the native reader.
-- One STABLE statement snapshot prevents pagination from inventing completeness.
create or replace function public.spike_read_budget_categories(p_account_id text)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  principal text;
  categories jsonb;
begin
  select p.id into principal from public.spike_principals p
    join public.spike_account_memberships m on m.principal_id = p.id
    where p.auth_user_id = (select auth.uid()) and m.account_id = p_account_id and m.state = 'active';
  if principal is null then
    raise exception using errcode = '42501', message = 'account_not_authorized';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'accountId', c.account_id, 'name', c.display_name, 'kind', c.kind,
    'lifecycle', c.lifecycle, 'isSystem', c.is_system,
    'excludesFromOverallBudget', c.excludes_from_overall_budget,
    'presentationOrder', c.presentation_order, 'revision', c.revision::text
  ) order by c.presentation_order, c.id), '[]'::jsonb) into categories
  from public.spike_budget_categories c where c.account_id = p_account_id;
  return jsonb_build_object('accountId', p_account_id, 'principalId', principal,
    'categories', categories, 'complete', true);
end
$$;
revoke all on function public.spike_read_budget_categories(text) from public, anon, service_role;
grant execute on function public.spike_read_budget_categories(text) to authenticated;
