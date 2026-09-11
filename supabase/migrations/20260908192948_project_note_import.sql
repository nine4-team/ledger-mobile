-- Operator-only historical import; no new-note command or authenticated API.
alter table public.spike_project_notes
  add constraint project_notes_import_scope_unique unique (account_id, project_id, id);

create table ledger_private.imported_project_note_sources (
  note_id text primary key,
  account_id text not null,
  project_id text not null,
  source_account_id text not null check (octet_length(source_account_id) between 1 and 1500 and source_account_id not in ('.', '..') and position('/' in source_account_id) = 0),
  source_project_id text not null check (octet_length(source_project_id) between 1 and 1500 and source_project_id not in ('.', '..') and position('/' in source_project_id) = 0),
  source_note_id text not null check (octet_length(source_note_id) between 1 and 1500 and source_note_id not in ('.', '..') and position('/' in source_note_id) = 0),
  source_bytes bytea not null check (octet_length(source_bytes) between 1 and 4194304),
  source_sha256 text generated always as (encode(extensions.digest(source_bytes, 'sha256'), 'hex')) stored,
  imported_projection jsonb not null check (jsonb_typeof(imported_projection) = 'object'),
  unique (source_account_id, source_project_id, source_note_id),
  foreign key (account_id, project_id, note_id)
    references public.spike_project_notes(account_id, project_id, id)
);
alter table ledger_private.imported_project_note_sources enable row level security;
alter table ledger_private.imported_project_note_sources force row level security;
revoke all on ledger_private.imported_project_note_sources from public, anon, authenticated, service_role;

create function ledger_private.reject_imported_project_note_change() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = 'Imported Project-note evidence is immutable';
end;
$$;
revoke all on function ledger_private.reject_imported_project_note_change() from public, anon, authenticated, service_role;
create trigger imported_project_note_immutable
  before update or delete on ledger_private.imported_project_note_sources
  for each row execute function ledger_private.reject_imported_project_note_change();
create trigger imported_project_note_no_truncate
  before truncate on ledger_private.imported_project_note_sources
  for each statement execute function ledger_private.reject_imported_project_note_change();

create function ledger_private.import_project_note(
  p_account_id text, p_project_id text, p_note_id text, p_note_text text,
  p_source text, p_original_creator_id text, p_creator_display_name text,
  p_created_by_principal_id text, p_created_at_ms bigint, p_created_at_submillis integer,
  p_last_edited_at_ms bigint, p_last_edited_at_submillis integer,
  p_source_account text, p_source_project text, p_source_note text, p_source_bytes bytea
) returns text language plpgsql security invoker set search_path = '' set timezone = 'UTC' as $$
declare
  proposed public.spike_project_notes;
  stored public.spike_project_notes;
  evidence ledger_private.imported_project_note_sources;
begin
  -- Serializes all imports for this exact existing parent before replay checks.
  perform 1 from public.spike_projects where account_id = p_account_id and id = p_project_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Note import requires the exact existing Account Project';
  end if;
  -- Bound values before interval arithmetic. Invalid precision is never rounded.
  if (p_created_at_ms is not null and p_created_at_ms not between -62135596800000 and 253402300799999)
    or (p_last_edited_at_ms is not null and p_last_edited_at_ms not between -62135596800000 and 253402300799999)
    or (p_created_at_ms is null and coalesce(p_created_at_submillis, 0) <> 0)
    or (p_last_edited_at_ms is null and coalesce(p_last_edited_at_submillis, 0) <> 0)
    or (p_created_at_ms is not null and p_created_at_submillis is null)
    or (p_last_edited_at_ms is not null and p_last_edited_at_submillis is null)
    or (p_created_at_submillis is not null and p_created_at_submillis not between 0 and 999999)
    or (p_last_edited_at_submillis is not null and p_last_edited_at_submillis not between 0 and 999999)
  then
    raise exception using errcode = '23514', message = 'Note import requires exact valid time components';
  end if;
  proposed.id := p_note_id;
  proposed.account_id := p_account_id;
  proposed.project_id := p_project_id;
  proposed.content_kind := 'visible';
  proposed.note_text := p_note_text;
  proposed.source := p_source;
  proposed.original_creator_id := p_original_creator_id;
  proposed.created_by_principal_id := p_created_by_principal_id;
  proposed.creator_display_name := p_creator_display_name;
  proposed.created_at_ms := p_created_at_ms;
  proposed.created_at_submillis := p_created_at_submillis;
  proposed.last_edited_at_ms := p_last_edited_at_ms;
  proposed.last_edited_at_submillis := p_last_edited_at_submillis;
  proposed.deleted_at_submillis := 0;
  proposed.revision := 0;
  if p_created_at_ms is not null then
    proposed.created_at := timestamptz '1970-01-01 00:00:00+00'
      + ((p_created_at_ms / 1000)::text || ' seconds')::interval
      + ((p_created_at_ms % 1000)::text || ' milliseconds')::interval;
  end if;
  if p_last_edited_at_ms is not null then
    proposed.last_edited_at := timestamptz '1970-01-01 00:00:00+00'
      + ((p_last_edited_at_ms / 1000)::text || ' seconds')::interval
      + ((p_last_edited_at_ms % 1000)::text || ' milliseconds')::interval;
  end if;
  select * into evidence from ledger_private.imported_project_note_sources where note_id = p_note_id;
  if found then
    select * into stored from public.spike_project_notes where id = p_note_id for update;
    if not found or row(evidence.account_id, evidence.project_id, evidence.source_account_id,
      evidence.source_project_id, evidence.source_note_id, evidence.source_bytes, evidence.imported_projection,
      to_jsonb(stored)) is distinct from row(p_account_id, p_project_id, p_source_account,
      p_source_project, p_source_note, p_source_bytes, to_jsonb(proposed), to_jsonb(proposed)) then
      raise exception using errcode = '22000', message = 'Note import conflicts with stored projection or source evidence';
    end if;
    return p_note_id;
  end if;
  insert into public.spike_project_notes select proposed.* on conflict do nothing;
  if not found then
    raise exception using errcode = '22000', message = 'Note import cannot replace an existing target';
  end if;
  insert into ledger_private.imported_project_note_sources (
    note_id, account_id, project_id, source_account_id, source_project_id, source_note_id, source_bytes, imported_projection
  ) values (p_note_id, p_account_id, p_project_id, p_source_account, p_source_project, p_source_note, p_source_bytes, to_jsonb(proposed))
  on conflict do nothing;
  if not found then
    raise exception using errcode = '22000', message = 'Note source is already mapped to another target';
  end if;
  return p_note_id;
end;
$$;
revoke all on function ledger_private.import_project_note(text,text,text,text,text,text,text,text,bigint,integer,bigint,integer,text,text,text,bytea)
  from public, anon, authenticated, service_role;
