create table public.spike_project_notes (
  id text primary key
    check (
      id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
      and octet_length(id) <= 128
    ),
  account_id text not null,
  project_id text not null,
  content_kind text not null check (content_kind in ('visible', 'tombstone')),
  note_text text,
  source text not null
    check (
      octet_length(source) between 1 and 64
    ),
  created_by_principal_id text not null references public.spike_principals(id),
  creator_display_name text,
  created_at timestamptz not null,
  created_at_ms bigint not null,
  revision numeric not null
    check (
      scale(revision) = 0
      and revision between 0::numeric and 18446744073709551615::numeric
    ),
  last_edited_by_principal_id text references public.spike_principals(id),
  last_edited_at timestamptz,
  last_edited_at_ms bigint,
  deleted_by_principal_id text references public.spike_principals(id),
  deleted_at timestamptz,
  deleted_at_ms bigint,
  constraint spike_project_notes_project_scope_fkey
    foreign key (account_id, project_id)
    references public.spike_projects(account_id, id),
  check (
    creator_display_name is null
    or translate(
      creator_display_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\200B\2028\2029\202F\205F\3000',
      ''
    ) <> ''
  ),
  check (
    (
      content_kind = 'visible'
      and note_text is not null
      and translate(
        note_text,
        U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\200B\2028\2029\202F\205F\3000',
        ''
      ) <> ''
      and deleted_by_principal_id is null
      and deleted_at is null
      and deleted_at_ms is null
    )
    or
    (
      content_kind = 'tombstone'
      and note_text is null
      and deleted_by_principal_id is not null
      and deleted_at is not null
      and deleted_at_ms is not null
    )
  ),
  check (
    (last_edited_by_principal_id is null and last_edited_at is null and last_edited_at_ms is null)
    or
    (last_edited_by_principal_id is not null and last_edited_at is not null and last_edited_at_ms is not null)
  ),
  check (
    pg_catalog.isfinite(created_at)
    and created_at = date_trunc('milliseconds', created_at)
    and created_at_ms = floor(extract(epoch from created_at) * 1000)::bigint
  ),
  check (
    last_edited_at is null
    or (
      pg_catalog.isfinite(last_edited_at)
      and last_edited_at = date_trunc('milliseconds', last_edited_at)
      and last_edited_at_ms = floor(extract(epoch from last_edited_at) * 1000)::bigint
      and created_at <= last_edited_at
    )
  ),
  check (
    deleted_at is null
    or (
      pg_catalog.isfinite(deleted_at)
      and deleted_at = date_trunc('milliseconds', deleted_at)
      and deleted_at_ms = floor(extract(epoch from deleted_at) * 1000)::bigint
      and created_at <= deleted_at
      and (last_edited_at is null or last_edited_at <= deleted_at)
    )
  )
);

create index spike_project_notes_project_history_idx
  on public.spike_project_notes (
    account_id,
    project_id,
    created_at_ms desc,
    id collate "C" desc
  );

create index spike_project_notes_creator_principal_idx
  on public.spike_project_notes (created_by_principal_id);

create index spike_project_notes_editor_principal_idx
  on public.spike_project_notes (last_edited_by_principal_id)
  where last_edited_by_principal_id is not null;

create index spike_project_notes_deleter_principal_idx
  on public.spike_project_notes (deleted_by_principal_id)
  where deleted_by_principal_id is not null;

alter table public.spike_project_notes enable row level security;
alter table public.spike_project_notes force row level security;

revoke all on table public.spike_project_notes
from public, anon, authenticated;

grant select on table public.spike_project_notes to authenticated;

create policy spike_project_notes_select_active_member
on public.spike_project_notes
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create function public.spike_list_project_notes(
  p_account_id text,
  p_project_id text,
  p_page_size integer,
  p_after_created_at_ms bigint,
  p_after_note_id text,
  p_query_fingerprint text
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_fingerprint_material text;
  v_expected_fingerprint text;
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;

  if p_account_id is null
    or p_account_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_account_id) > 128
    or p_project_id is null
    or p_project_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_project_id) > 128
    or p_page_size is null
    or p_page_size not between 1 and 200
    or (p_after_created_at_ms is null) <> (p_after_note_id is null)
    or (
      p_after_note_id is not null
      and (
        p_after_note_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
        or octet_length(p_after_note_id) > 128
      )
    )
    or p_query_fingerprint is null
    or p_query_fingerprint !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode = '22023',
      message = 'project note page request invalid';
  end if;

  v_fingerprint_material := '{"accountId":'
    || pg_catalog.to_json(p_account_id)::text
    || case
      when p_after_created_at_ms is null then ''
      else ',"after":{"accountId":'
        || pg_catalog.to_json(p_account_id)::text
        || ',"createdAt":' || p_after_created_at_ms::text
        || ',"noteId":' || pg_catalog.to_json(p_after_note_id)::text
        || ',"projectId":' || pg_catalog.to_json(p_project_id)::text
        || '}'
    end
    || ',"pageSize":' || p_page_size::text
    || ',"projectId":' || pg_catalog.to_json(p_project_id)::text
    || '}';
  v_expected_fingerprint := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(v_fingerprint_material, 'UTF8'), 'sha256'),
    'hex'
  );

  if p_query_fingerprint is distinct from v_expected_fingerprint then
    raise exception using
      errcode = '22023',
      message = 'project note query fingerprint mismatch';
  end if;

  perform 1
  from public.spike_projects as project
  where project.account_id = p_account_id
    and project.id = p_project_id;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'project note scope not authorized';
  end if;

  with candidate_rows as materialized (
    select note.*
    from public.spike_project_notes as note
    where note.account_id = p_account_id
      and note.project_id = p_project_id
      and (
        p_after_created_at_ms is null
        or note.created_at_ms < p_after_created_at_ms
        or (
          note.created_at_ms = p_after_created_at_ms
          and note.id < p_after_note_id collate "C"
        )
      )
    order by note.created_at_ms desc, note.id collate "C" desc
    limit p_page_size + 1
  ),
  page_rows as materialized (
    select candidate.*
    from candidate_rows as candidate
    order by candidate.created_at_ms desc, candidate.id collate "C" desc
    limit p_page_size
  ),
  page_metadata as (
    select count(*)::integer as candidate_count
    from candidate_rows
  )
  select jsonb_build_object(
    'account_id', p_account_id,
    'project_id', p_project_id,
    'page_size', p_page_size,
    'query_fingerprint', p_query_fingerprint,
    'rows', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'account_id', page.account_id,
            'project_id', page.project_id,
            'content_kind', page.content_kind,
            'note_text', page.note_text,
            'source', page.source,
            'created_by_principal_id', page.created_by_principal_id,
            'creator_display_name', page.creator_display_name,
            'created_at_ms', page.created_at_ms,
            'revision', page.revision::text,
            'last_edited_by_principal_id', page.last_edited_by_principal_id,
            'last_edited_at_ms', page.last_edited_at_ms,
            'deleted_by_principal_id', page.deleted_by_principal_id,
            'deleted_at_ms', page.deleted_at_ms
          )
          order by page.created_at_ms desc, page.id collate "C" desc
        )
        from page_rows as page
      ),
      '[]'::jsonb
    ),
    'is_complete_for_project_history', metadata.candidate_count <= p_page_size,
    'next_cursor', case
      when metadata.candidate_count <= p_page_size then null
      else (
        select jsonb_build_object(
          'account_id', boundary.account_id,
          'project_id', boundary.project_id,
          'created_at_ms', boundary.created_at_ms,
          'note_id', boundary.id
        )
        from page_rows as boundary
        order by boundary.created_at_ms asc, boundary.id collate "C" asc
        limit 1
      )
    end
  )
  into v_result
  from page_metadata as metadata;

  return v_result;
end
$$;

revoke all on function public.spike_list_project_notes(
  text, text, integer, bigint, text, text
) from public, anon, service_role;

grant execute on function public.spike_list_project_notes(
  text, text, integer, bigint, text, text
) to authenticated;
