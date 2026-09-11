create table ledger_private.imported_project_legacy_note_sources (
  project_id text primary key,
  account_id text not null,
  source_account_id text not null check (octet_length(source_account_id) between 1 and 1500 and source_account_id not in ('.', '..') and position('/' in source_account_id) = 0),
  source_document_id text not null check (octet_length(source_document_id) between 1 and 1500 and source_document_id not in ('.', '..') and position('/' in source_document_id) = 0),
  source_bytes bytea not null check (octet_length(source_bytes) between 1 and 4194304),
  source_sha256 text generated always as (encode(extensions.digest(source_bytes, 'sha256'), 'hex')) stored,
  imported_notes text,
  unique (source_account_id, source_document_id),
  foreign key (account_id, project_id) references public.spike_projects(account_id, id)
);
create index imported_project_legacy_note_sources_account_idx
  on ledger_private.imported_project_legacy_note_sources(account_id, project_id);
alter table ledger_private.imported_project_legacy_note_sources enable row level security;
alter table ledger_private.imported_project_legacy_note_sources force row level security;
revoke all on ledger_private.imported_project_legacy_note_sources from public, anon, authenticated, service_role;

create function ledger_private.reject_imported_project_legacy_note_change() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = 'Imported Project legacy-note evidence is immutable';
end;
$$;
revoke all on function ledger_private.reject_imported_project_legacy_note_change() from public, anon, authenticated, service_role;
create trigger imported_project_legacy_note_immutable
  before update or delete on ledger_private.imported_project_legacy_note_sources
  for each row execute function ledger_private.reject_imported_project_legacy_note_change();
create trigger imported_project_legacy_note_no_truncate
  before truncate on ledger_private.imported_project_legacy_note_sources
  for each statement execute function ledger_private.reject_imported_project_legacy_note_change();

-- Operator-only import. NULL represents absent/null text; complete source bytes
-- retain that distinction. No new note, author/date, lifecycle or revision intent.
create function ledger_private.import_project_legacy_notes(
  p_account_id text, p_project_id text, p_notes text,
  p_source_account text, p_source_document text, p_source_bytes bytea
) returns text language plpgsql security invoker set search_path = '' as $$
declare
  stored public.spike_projects;
  evidence ledger_private.imported_project_legacy_note_sources;
begin
  -- Serialize same-target imports before inspecting either text or provenance.
  select * into stored from public.spike_projects
    where account_id = p_account_id and id = p_project_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Legacy-note import requires the exact existing Account Project';
  end if;
  select * into evidence from ledger_private.imported_project_legacy_note_sources
    where project_id = p_project_id;
  if found then
    if row(evidence.account_id, evidence.source_account_id, evidence.source_document_id,
           evidence.source_bytes, evidence.imported_notes, stored.legacy_notes)
       is distinct from row(p_account_id, p_source_account, p_source_document,
                            p_source_bytes, p_notes, p_notes) then
      raise exception using errcode = '22000', message = 'Legacy-note import conflicts with stored text or source evidence';
    end if;
    return p_project_id;
  end if;
  if stored.legacy_notes is not null and stored.legacy_notes is distinct from p_notes then
    raise exception using errcode = '22000', message = 'Legacy-note import cannot replace existing text';
  end if;
  insert into ledger_private.imported_project_legacy_note_sources(
    project_id, account_id, source_account_id, source_document_id, source_bytes, imported_notes)
    values (p_project_id, p_account_id, p_source_account, p_source_document, p_source_bytes, p_notes)
    on conflict do nothing;
  if not found then
    raise exception using errcode = '22000', message = 'Legacy-note source is already mapped to another Project';
  end if;
  if stored.legacy_notes is distinct from p_notes then
    update public.spike_projects set legacy_notes = p_notes
      where account_id = p_account_id and id = p_project_id;
  end if;
  return p_project_id;
end;
$$;
revoke all on function ledger_private.import_project_legacy_notes(text,text,text,text,text,bytea)
  from public, anon, authenticated, service_role;
