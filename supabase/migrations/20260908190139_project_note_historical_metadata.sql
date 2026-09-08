-- A-031: missing historical metadata is not an authenticated author or import time.
-- Existing millisecond columns plus the submillisecond remainder are exact time;
-- timestamptz columns remain their existing millisecond presentation projection.
alter table public.spike_project_notes
  alter column created_by_principal_id drop not null,
  alter column created_at drop not null,
  alter column created_at_ms drop not null,
  add column original_creator_id text,
  add column created_at_submillis integer default 0,
  add column last_edited_at_submillis integer default 0,
  add column deleted_at_submillis integer default 0;

-- Replace only the historical editor/time coupling, not scope or tenant checks.
do $$
declare
  v_constraint text;
  v_count integer;
begin
  select count(*), min(conname::text) into v_count, v_constraint
  from pg_catalog.pg_constraint
  where conrelid = 'public.spike_project_notes'::regclass
    and contype = 'c'
    and pg_catalog.pg_get_constraintdef(oid) like '%last_edited_by_principal_id IS NULL%';
  if v_count <> 1 then
    raise exception 'expected exactly one note editor/time coupling constraint';
  end if;
  execute pg_catalog.format('alter table public.spike_project_notes drop constraint %I', v_constraint);
end;
$$;

alter table public.spike_project_notes
  add constraint project_notes_known_editor_has_time check (
    last_edited_by_principal_id is null
    or (last_edited_at is not null and last_edited_at_ms is not null)
  ),
  add constraint project_notes_exact_time_components check (
    (created_at is null) = (created_at_ms is null)
    and ((created_at_ms is null and coalesce(created_at_submillis, 0) = 0)
      or (created_at_ms is not null and created_at_submillis is not null))
    and (last_edited_at is null) = (last_edited_at_ms is null)
    and ((last_edited_at_ms is null and coalesce(last_edited_at_submillis, 0) = 0)
      or (last_edited_at_ms is not null and last_edited_at_submillis is not null))
    and (deleted_at is null) = (deleted_at_ms is null)
    and ((deleted_at_ms is null and coalesce(deleted_at_submillis, 0) = 0)
      or (deleted_at_ms is not null and deleted_at_submillis is not null))
    and (created_at_submillis is null or created_at_submillis between 0 and 999999)
    and (last_edited_at_submillis is null or last_edited_at_submillis between 0 and 999999)
    and (deleted_at_submillis is null or deleted_at_submillis between 0 and 999999)
    and (created_at_ms is null or created_at_ms between -62135596800000 and 253402300799999)
    and (last_edited_at_ms is null or last_edited_at_ms between -62135596800000 and 253402300799999)
    and (deleted_at_ms is null or deleted_at_ms between -62135596800000 and 253402300799999)
  ),
  add constraint project_notes_exact_chronology check (
    (created_at_ms is null or last_edited_at_ms is null
      or (created_at_ms, created_at_submillis) <= (last_edited_at_ms, last_edited_at_submillis))
    and (created_at_ms is null or deleted_at_ms is null
      or (created_at_ms, created_at_submillis) <= (deleted_at_ms, deleted_at_submillis))
    and (last_edited_at_ms is null or deleted_at_ms is null
      or (last_edited_at_ms, last_edited_at_submillis) <= (deleted_at_ms, deleted_at_submillis))
  );

create index project_notes_exact_history_idx on public.spike_project_notes (
  account_id, project_id, created_at_ms desc nulls last,
  (coalesce(created_at_submillis, 0)) desc, id collate "C" desc
);

-- Replace the not-yet-released target RPC rather than maintain competing cursors.
drop function public.spike_list_project_notes(text,text,integer,bigint,text,text);
create function public.spike_list_project_notes(
  p_account_id text, p_project_id text, p_page_size integer,
  p_after_created_timestamp jsonb, p_after_note_id text, p_query_fingerprint text
) returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_seconds bigint;
  v_nanos integer;
  v_after_ms bigint;
  v_after_submillis integer;
  v_material text;
  v_expected text;
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;
  if p_account_id is null or p_account_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_account_id) > 128
    or p_project_id is null or p_project_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_project_id) > 128
    or p_page_size is null or p_page_size not between 1 and 200
    or (p_after_note_id is not null and (p_after_note_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(p_after_note_id) > 128))
    or p_query_fingerprint is null or p_query_fingerprint !~ '^[0-9a-f]{64}$'
  then
    raise exception using errcode = '22023', message = 'project note page request invalid';
  end if;
  if p_after_created_timestamp is not null then
    if p_after_note_id is null or jsonb_typeof(p_after_created_timestamp) <> 'object'
      or (p_after_created_timestamp - array['secondsSince1970','nanoseconds']) <> '{}'::jsonb
      or jsonb_typeof(p_after_created_timestamp->'secondsSince1970') is distinct from 'number'
      or jsonb_typeof(p_after_created_timestamp->'nanoseconds') is distinct from 'number'
      or (p_after_created_timestamp->>'secondsSince1970') !~ '^-?[0-9]+$'
      or (p_after_created_timestamp->>'nanoseconds') !~ '^[0-9]+$'
    then
      raise exception using errcode = '22023', message = 'project note timestamp invalid';
    end if;
    if (p_after_created_timestamp->>'secondsSince1970')::numeric not between -62135596800 and 253402300799
      or (p_after_created_timestamp->>'nanoseconds')::numeric not between 0 and 999999999
    then
      raise exception using errcode = '22023', message = 'project note timestamp invalid';
    end if;
    v_seconds := (p_after_created_timestamp->>'secondsSince1970')::bigint;
    v_nanos := (p_after_created_timestamp->>'nanoseconds')::integer;
    v_after_ms := v_seconds * 1000 + v_nanos / 1000000;
    v_after_submillis := v_nanos % 1000000;
  end if;
  v_material := '{"accountId":' || pg_catalog.to_json(p_account_id)::text
    || case when p_after_note_id is null then '' else
      ',"after":{"accountId":' || pg_catalog.to_json(p_account_id)::text
      || case when p_after_created_timestamp is null then '' else
        ',"createdTimestamp":{"nanoseconds":' || v_nanos::text
        || ',"secondsSince1970":' || v_seconds::text || '}' end
      || ',"noteId":' || pg_catalog.to_json(p_after_note_id)::text
      || ',"projectId":' || pg_catalog.to_json(p_project_id)::text || '}' end
    || ',"pageSize":' || p_page_size::text
    || ',"projectId":' || pg_catalog.to_json(p_project_id)::text || '}';
  v_expected := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_material,'UTF8'),'sha256'),'hex');
  if p_query_fingerprint is distinct from v_expected then
    raise exception using errcode = '22023', message = 'project note query fingerprint mismatch';
  end if;
  perform 1 from public.spike_projects where account_id = p_account_id and id = p_project_id;
  if not found then
    raise exception using errcode = '42501', message = 'project note scope not authorized';
  end if;
  with candidates as materialized (
    select note.* from public.spike_project_notes note
    where note.account_id = p_account_id and note.project_id = p_project_id
      and (p_after_note_id is null
        or (v_after_ms is null and note.created_at_ms is null and note.id < p_after_note_id collate "C")
        or (v_after_ms is not null and (note.created_at_ms is null
          or note.created_at_ms < v_after_ms
          or (note.created_at_ms = v_after_ms and (
            note.created_at_submillis < v_after_submillis
            or (note.created_at_submillis = v_after_submillis and note.id < p_after_note_id collate "C")
          )))))
    order by note.created_at_ms desc nulls last, coalesce(note.created_at_submillis, 0) desc, note.id collate "C" desc
    limit p_page_size + 1
  ), page as materialized (
    select * from candidates
    order by created_at_ms desc nulls last, coalesce(created_at_submillis, 0) desc, id collate "C" desc
    limit p_page_size
  )
  select jsonb_build_object(
    'account_id', p_account_id, 'project_id', p_project_id, 'page_size', p_page_size,
    'query_fingerprint', p_query_fingerprint,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'account_id', account_id, 'project_id', project_id,
      'content_kind', content_kind, 'note_text', note_text, 'source', source,
      'created_by_principal_id', created_by_principal_id, 'original_creator_id', original_creator_id,
      'creator_display_name', creator_display_name,
      'created_at_ms', created_at_ms, 'created_at_submillis', created_at_submillis,
      'revision', revision::text,
      'last_edited_by_principal_id', last_edited_by_principal_id,
      'last_edited_at_ms', last_edited_at_ms, 'last_edited_at_submillis', last_edited_at_submillis,
      'deleted_by_principal_id', deleted_by_principal_id,
      'deleted_at_ms', deleted_at_ms, 'deleted_at_submillis', deleted_at_submillis
    ) order by created_at_ms desc nulls last, coalesce(created_at_submillis, 0) desc, id collate "C" desc) from page),'[]'::jsonb),
    'is_complete_for_project_history', (select count(*) <= p_page_size from candidates),
    'next_cursor', case when (select count(*) <= p_page_size from candidates) then null else (
      select jsonb_build_object('account_id', account_id, 'project_id', project_id,
        'created_at_ms', created_at_ms, 'created_at_submillis', created_at_submillis, 'note_id', id)
      from page order by created_at_ms asc nulls first, coalesce(created_at_submillis, 0) asc, id collate "C" asc limit 1
    ) end
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.spike_list_project_notes(text,text,integer,jsonb,text,text) from public, anon, service_role;
grant execute on function public.spike_list_project_notes(text,text,integer,jsonb,text,text) to authenticated;
