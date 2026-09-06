begin;
select plan(45);

create function pg_temp.note_fingerprint(
  account_id text,
  project_id text,
  page_size integer,
  after_created_at_ms bigint default null,
  after_note_id text default null
)
returns text
language sql
immutable
as $$
  select encode(
    digest(
      convert_to(
        '{"accountId":' || to_json(account_id)::text
        || case when after_created_at_ms is null then '' else
          ',"after":{"accountId":' || to_json(account_id)::text
          || ',"createdAt":' || after_created_at_ms::text
          || ',"noteId":' || to_json(after_note_id)::text
          || ',"projectId":' || to_json(project_id)::text || '}'
        end
        || ',"pageSize":' || page_size::text
        || ',"projectId":' || to_json(project_id)::text || '}',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$$;

create function pg_temp.archive_operation_id(account_id text, operation_key text)
returns text
language sql
immutable
as $$
  select 'project-archive-'
    || encode(digest(convert_to(account_id, 'UTF8'), 'sha256'), 'hex')
    || '-'
    || substring(md5(operation_key) from 1 for 8) || '-'
    || substring(md5(operation_key) from 9 for 4) || '-'
    || substring(md5(operation_key) from 13 for 4) || '-'
    || substring(md5(operation_key) from 17 for 4) || '-'
    || substring(md5(operation_key) from 21 for 12)
$$;

create function pg_temp.archive_envelope(
  operation_id text,
  project_id text,
  expected_revision text
)
returns text
language sql
immutable
as $$
  select format(
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788609600000,"contractVersion":"project-archive-v1","operationId":%s,"payload":{"projectId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"project"}}}]}',
    to_json(operation_id)::text,
    to_json(project_id)::text,
    expected_revision,
    to_json(project_id)::text
  )
$$;

select ok(
  to_regclass('public.spike_project_notes') is not null,
  'the isolated Project-note relation exists'
);

select is(
  (
    select string_agg(
      column_name || ':' || data_type || ':' || is_nullable,
      ',' order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'spike_project_notes'
  ),
  'id:text:NO,account_id:text:NO,project_id:text:NO,content_kind:text:NO,note_text:text:YES,source:text:NO,created_by_principal_id:text:NO,creator_display_name:text:YES,created_at:timestamp with time zone:NO,created_at_ms:bigint:NO,revision:numeric:NO,last_edited_by_principal_id:text:YES,last_edited_at:timestamp with time zone:YES,last_edited_at_ms:bigint:YES,deleted_by_principal_id:text:YES,deleted_at:timestamp with time zone:YES,deleted_at_ms:bigint:YES',
  'the relation has the exact read and audit projection'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_project_notes'::regclass
      and conname = 'spike_project_notes_pkey'
      and contype = 'p'
  ),
  'stable note identity is the primary key'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_project_notes'::regclass
      and conname = 'spike_project_notes_project_scope_fkey'
      and pg_get_constraintdef(oid) like
        'FOREIGN KEY (account_id, project_id) REFERENCES spike_projects(account_id, id)%'
  ),
  'the parent relationship is exact Account and Project scope'
);

select ok(
  pg_get_indexdef('public.spike_project_notes_project_history_idx'::regclass)
    like '%(account_id, project_id, created_at_ms DESC, id COLLATE "C" DESC)',
  'the deterministic Project-history page index exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.spike_project_notes'::regclass),
  'row-level security is enabled'
);

select ok(
  (select relforcerowsecurity from pg_class where oid = 'public.spike_project_notes'::regclass),
  'row-level security is forced for defense in depth'
);

select ok(
  has_table_privilege('authenticated', 'public.spike_project_notes', 'SELECT'),
  'authenticated has the required table SELECT grant'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_project_notes',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'authenticated has no direct note write or schema-adjacent privilege'
);

select ok(
  not has_table_privilege('anon', 'public.spike_project_notes', 'SELECT,INSERT,UPDATE,DELETE'),
  'anonymous has no note table privilege'
);

select is(
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename = 'spike_project_notes'),
  1::bigint,
  'the table has exactly one policy'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'spike_project_notes'
      and policyname = 'spike_project_notes_select_active_member'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%has_active_membership%account_id%'
  ),
  'the sole policy requires active Account membership'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.spike_list_project_notes(text,text,integer,bigint,text,text)',
    'EXECUTE'
  ),
  'authenticated may execute the bounded read RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.spike_list_project_notes(text,text,integer,bigint,text,text)',
    'EXECUTE'
  ),
  'anonymous may not execute the read RPC'
);

select ok(
  not (select prosecdef from pg_proc
       where oid = 'public.spike_list_project_notes(text,text,integer,bigint,text,text)'::regprocedure),
  'the public read RPC is security invoker'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-0000-0000-000000000006',
  'authenticated', 'authenticated', 'note-revoked@ledger-spike.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.spike_principals (id, auth_user_id)
values ('principal-note-revoked', '10000000-0000-0000-0000-000000000006');

insert into public.spike_account_memberships (
  account_id, principal_id, role, state, can_manage_clients,
  can_manage_projects, can_manage_project_budgets, financial_access
) values (
  'account-primary', 'principal-note-revoked', 'employee', 'removed',
  false, false, false, 'none'
);

insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms, created_by_principal_id
) values (
  'client-note-other', 'account-other', 'Other Note Client', 'active', 1,
  '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
  1788609600000, 1788609600000, 'principal-other'
);

insert into public.spike_projects (
  id, account_id, client_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms, created_by_principal_id
) values
  (
    'project-note-active', 'account-primary', 'client-existing', 'Active Notes',
    'active', 4, '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-owner'
  ),
  (
    'project-note-archived', 'account-primary', 'client-existing', 'Archived Notes',
    'archived', 8, '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-owner'
  ),
  (
    'project-note-empty', 'account-primary', 'client-existing', 'Empty Notes',
    'active', 1, '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-owner'
  ),
  (
    'project-note-other', 'account-other', 'client-note-other', 'Other Notes',
    'active', 1, '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-other'
  );

insert into public.spike_project_notes (
  id, account_id, project_id, content_kind, note_text, source,
  created_by_principal_id, creator_display_name, created_at, created_at_ms,
  revision, last_edited_by_principal_id, last_edited_at, last_edited_at_ms,
  deleted_by_principal_id, deleted_at, deleted_at_ms
) values
  (
    'note-z', 'account-primary', 'project-note-active', 'tombstone', null, 'mcp',
    'principal-owner', 'Owner', '2026-09-05T12:00:02Z', 1788609602000,
    3, 'principal-restricted', '2026-09-05T12:00:03Z', 1788609603000,
    'principal-restricted', '2026-09-05T12:00:04Z', 1788609604000
  ),
  (
    'note-b', 'account-primary', 'project-note-active', 'visible',
    'Revised delivery window', 'text', 'principal-owner', 'Owner',
    '2026-09-05T12:00:01Z', 1788609601000, 18446744073709551615,
    'principal-restricted', '2026-09-05T12:00:03Z', 1788609603000,
    null, null, null
  ),
  (
    'note-a', 'account-primary', 'project-note-active', 'visible',
    'Original hardware selection', 'text', 'principal-owner', null,
    '2026-09-05T12:00:01Z', 1788609601000, 0,
    null, null, null, null, null, null
  ),
  (
    'note-archived', 'account-primary', 'project-note-archived', 'visible',
    'Preserved after archive', 'text', 'principal-owner', 'Owner',
    '2026-09-05T12:00:01Z', 1788609601000, 2,
    null, null, null, null, null, null
  ),
  (
    'note-other', 'account-other', 'project-note-other', 'visible',
    'Other Account', 'text', 'principal-other', null,
    '2026-09-05T12:00:01Z', 1788609601000, 1,
    null, null, null, null, null, null
  );

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-cross-account', 'account-other', 'project-note-active', 'visible',
      'Invalid', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600000, 1
    )$$,
  '23503', null,
  'a note cannot cross Account and Project scope'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-fractional', 'account-primary', 'project-note-active', 'visible',
      'Invalid', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600000, 1.5
    )$$,
  '23514', null,
  'fractional revisions are rejected instead of rounded'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-revision-overflow', 'account-primary', 'project-note-active', 'visible',
      'Invalid', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600000, 18446744073709551616
    )$$,
  '23514', null,
  'revisions above UInt64 maximum are rejected'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-live-tombstone', 'account-primary', 'project-note-active', 'tombstone',
      'Leaked prose', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600000, 1
    )$$,
  '23514', null,
  'a tombstone cannot retain live note text'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-time-mismatch', 'account-primary', 'project-note-active', 'visible',
      'Invalid', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600001, 1
    )$$,
  '23514', null,
  'timestamp and canonical epoch-millisecond evidence cannot diverge'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-foundation-blank-text', 'account-primary', 'project-note-active', 'visible',
      U&'\0085\200B', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600000, 1
    )$$,
  '23514', null,
  'Foundation whitespace-only note text is rejected at the database boundary'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, creator_display_name, created_at, created_at_ms, revision
    ) values (
      'note-foundation-blank-creator', 'account-primary', 'project-note-active', 'visible',
      'Visible', 'text', 'principal-owner', U&'\0085\200B',
      '2026-09-05T12:00:00Z', 1788609600000, 1
    )$$,
  '23514', null,
  'Foundation whitespace-only creator display name is rejected at the database boundary'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select string_agg(id, ',' order by created_at_ms desc, id collate "C" desc)
   from public.spike_project_notes where project_id = 'project-note-active'),
  'note-z,note-b,note-a',
  'an active owner reads exact deterministic Project-note history'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-active', 2, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-active', 2)
  ) #>> '{rows,1,revision}'),
  '18446744073709551615',
  'the RPC returns full UInt64 revision as canonical decimal text'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-active', 2, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-active', 2)
  ) #>> '{rows,0,id}'),
  'note-z',
  'the first bounded row is newest'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-active', 2, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-active', 2)
  ) #>> '{next_cursor,note_id}'),
  'note-b',
  'the continuation cursor is the final exposed row boundary'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-active', 2, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-active', 2)
  ) ->> 'is_complete_for_project_history')::boolean,
  false,
  'a page with a lookahead row is not complete history'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-active', 2, 1788609601000, 'note-b',
    pg_temp.note_fingerprint(
      'account-primary', 'project-note-active', 2, 1788609601000, 'note-b'
    )
  ) #>> '{rows,0,id}'),
  'note-a',
  'the exact timestamp-and-ID cursor continues after tied rows'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-active', 2, 1788609601000, 'note-b',
    pg_temp.note_fingerprint(
      'account-primary', 'project-note-active', 2, 1788609601000, 'note-b'
    )
  ) ->> 'is_complete_for_project_history')::boolean,
  true,
  'the final keyset page reports complete older history'
);

select is(
  jsonb_array_length(public.spike_list_project_notes(
    'account-primary', 'project-note-empty', 200, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-empty', 200)
  ) -> 'rows'),
  0,
  'an authorized empty Project returns an empty bounded page'
);

select is(
  (public.spike_list_project_notes(
    'account-primary', 'project-note-archived', 20, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-archived', 20)
  ) #>> '{rows,0,id}'),
  'note-archived',
  'archived Project note history remains readable'
);

select throws_ok(
  $$select public.spike_list_project_notes(
      'account-primary', 'project-note-active', 0, null, null, repeat('a', 64)
    )$$,
  '22023', 'project note page request invalid',
  'the RPC rejects an out-of-range page size'
);

select throws_ok(
  $$select public.spike_list_project_notes(
      'account-primary', 'project-note-active', 2, null, null, repeat('a', 64)
    )$$,
  '22023', 'project note query fingerprint mismatch',
  'the RPC rejects a fingerprint not bound to the exact query'
);

select throws_ok(
  $$select public.spike_list_project_notes(
      'account-other', 'project-note-other', 2, null, null,
      pg_temp.note_fingerprint('account-other', 'project-note-other', 2)
    )$$,
  '42501', 'project note scope not authorized',
  'a caller-selected foreign Account and Project cannot widen authority'
);

select throws_ok(
  $$select public.spike_list_project_notes(
      'account-primary', 'project-note-missing', 2, null, null,
      pg_temp.note_fingerprint('account-primary', 'project-note-missing', 2)
    )$$,
  '42501', 'project note scope not authorized',
  'missing and unauthorized Project scopes share one bounded failure'
);

select throws_ok(
  $$insert into public.spike_project_notes (
      id, account_id, project_id, content_kind, note_text, source,
      created_by_principal_id, created_at, created_at_ms, revision
    ) values (
      'note-direct', 'account-primary', 'project-note-active', 'visible',
      'Denied', 'text', 'principal-owner', '2026-09-05T12:00:00Z',
      1788609600000, 1
    )$$,
  '42501', 'permission denied for table spike_project_notes',
  'authenticated cannot directly insert a note'
);

select throws_ok(
  $$update public.spike_project_notes set note_text = 'Changed' where id = 'note-a'$$,
  '42501', 'permission denied for table spike_project_notes',
  'authenticated cannot directly update a note'
);

select throws_ok(
  $$delete from public.spike_project_notes where id = 'note-a'$$,
  '42501', 'permission denied for table spike_project_notes',
  'authenticated cannot directly delete a note'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_project_notes),
  0::bigint,
  'a removed member cannot enumerate retained Project-note rows'
);

select throws_ok(
  $$select public.spike_list_project_notes(
      'account-primary', 'project-note-active', 2, null, null,
      pg_temp.note_fingerprint('account-primary', 'project-note-active', 2)
    )$$,
  '42501', 'project note scope not authorized',
  'a removed member receives the same bounded RPC scope failure'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

create temporary table note_before_archive as
select jsonb_agg(to_jsonb(note) order by note.id) as rows
from public.spike_project_notes as note
where note.project_id = 'project-note-active';

select is(
  (
    with identity as (
      select pg_temp.archive_operation_id('account-primary', 'note-preservation') as value
    ), envelope as (
      select pg_temp.archive_envelope(identity.value, 'project-note-active', '4') as value
      from identity
    )
    select result.phase
    from identity cross join envelope
    cross join lateral public.spike_archive_project(
      identity.value, 'account-primary', 'principal-owner', 'project-archive-v1',
      '2026-09-05T12:00:00Z', 'project-note-active', '4',
      encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
      envelope.value
    ) as result
  ),
  'applied',
  'the existing Project archive operation applies unchanged'
);

select is(
  (select lifecycle from public.spike_projects where id = 'project-note-active'),
  'archived',
  'the reused operation archives only the Project lifecycle'
);

select is(
  (select jsonb_agg(to_jsonb(note) order by note.id)
   from public.spike_project_notes as note
   where note.project_id = 'project-note-active'),
  (select rows from note_before_archive),
  'archive preserves every note byte and audit field'
);

select is(
  jsonb_array_length(public.spike_list_project_notes(
    'account-primary', 'project-note-active', 20, null, null,
    pg_temp.note_fingerprint('account-primary', 'project-note-active', 20)
  ) -> 'rows'),
  3,
  'the same authorized history remains readable after archive'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$select public.spike_list_project_notes(
      'account-primary', 'project-note-active', 2, null, null, repeat('a', 64)
    )$$,
  '42501',
  'permission denied for function spike_list_project_notes',
  'anonymous callers cannot execute the Project-note RPC'
);

select * from finish();
rollback;
