begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
select id,'account-primary','client-existing','Note import',now(),now(),1,1,'principal-owner'
from unnest(array['note-import-project','note-import-second']) id;
create temporary table note_import_parent_before as
select id,to_jsonb(p) as projection from public.spike_projects p where id like 'note-import-%';
create function pg_temp.import_note(
  p_note text default 'imported-note', p_text text default E'  Original\n第二行  ',
  p_source_note text default 'source-note', p_bytes bytea default decode('00ff7b7d','hex'),
  p_account text default 'account-primary', p_project text default 'note-import-project',
  p_created bigint default 1788609600000, p_remainder integer default 123456,
  p_updated bigint default 1788609600001, p_updated_remainder integer default 654321,
  p_principal text default null
) returns text language sql as $$
  select ledger_private.import_project_note(p_account,p_project,p_note,p_text,'mcp','mcp-agent','AI Assistant',
    p_principal,p_created,p_remainder,p_updated,p_updated_remainder,
    'source-account','source-project',p_source_note,p_bytes)
$$;
select is(pg_temp.import_note(),'imported-note','Import returns stable note identity');
select is((select note_text from public.spike_project_notes where id='imported-note'),E'  Original\n第二行  ','Exact source text preserved');
select is((select jsonb_build_object('creator',created_by_principal_id,'original',original_creator_id,
  'editedBy',last_edited_by_principal_id,'remainder',created_at_submillis,'updatedRemainder',last_edited_at_submillis,'revision',revision)
  from public.spike_project_notes where id='imported-note'),
  '{"creator":null,"original":"mcp-agent","editedBy":null,"remainder":123456,"updatedRemainder":654321,"revision":0}'::jsonb,
  'Raw MCP author is not invented as an authenticated creator or editor');
select is((select source_bytes from ledger_private.imported_project_note_sources where note_id='imported-note'),decode('00ff7b7d','hex'),'Full binary evidence preserved');
select is((select source_sha256 from ledger_private.imported_project_note_sources where note_id='imported-note'),encode(digest(decode('00ff7b7d','hex'),'sha256'),'hex'),'Evidence digest derives from full bytes');
create temporary table imported_note_version as select ctid::text as version from public.spike_project_notes where id='imported-note';
set local timezone='America/Los_Angeles';
select is(pg_temp.import_note(),'imported-note','Exact retry remains stable across caller timezone');
set local timezone='UTC';
select is((select ctid::text from public.spike_project_notes where id='imported-note'),(select version from imported_note_version),'Exact retry performs no update');
select is((select count(*) from ledger_private.imported_project_note_sources),1::bigint,'Retry adds no evidence');
select throws_ok($$select pg_temp.import_note(p_text=>'Changed')$$,'22000',null,'Changed text conflicts');
select throws_ok($$select pg_temp.import_note(p_remainder=>123457)$$,'22000',null,'Changed nanosecond conflicts');
select throws_ok($$select pg_temp.import_note(p_principal=>'principal-owner')$$,'22000',null,'Changed principal attribution conflicts');
select throws_ok($$select pg_temp.import_note(p_source_note=>'changed')$$,'22000',null,'Changed source identity conflicts');
select throws_ok($$select pg_temp.import_note(p_bytes=>'\x01'::bytea)$$,'22000',null,'Changed source bytes conflict');
select throws_ok($$select pg_temp.import_note(p_account=>'account-other')$$,'23503',null,'Cross-Account parent rejected');
select throws_ok($$select pg_temp.import_note(p_project=>'missing')$$,'23503',null,'Missing parent rejected');
select throws_ok($$select pg_temp.import_note(p_note=>'second-note',p_project=>'note-import-second')$$,'22000',null,'One source cannot map to a second target');
select is((select count(*) from public.spike_project_notes where id='second-note'),0::bigint,'Source collision rolls back provisional target');
select is(pg_temp.import_note(p_note=>'undated-note',p_source_note=>'undated',p_created=>null,p_remainder=>null),
  'undated-note','Unknown creation and known update are preserved independently');
select ok((select created_at is null and created_at_ms is null and created_by_principal_id is null
  and last_edited_at_ms=1788609600001 and last_edited_by_principal_id is null
  from public.spike_project_notes where id='undated-note'),'No creation time or editor is fabricated');
select is(pg_temp.import_note(p_note=>'preepoch-note',p_source_note=>'preepoch',p_created=>-1,p_remainder=>999999,p_updated=>null,p_updated_remainder=>0),
  'preepoch-note','Negative epoch precision imports without floating point rounding');
select is((select created_at from public.spike_project_notes where id='preepoch-note'),timestamptz '1969-12-31 23:59:59.999+00','Millisecond display projection is exact before epoch');
select throws_ok($$select pg_temp.import_note(p_note=>'bad-note',p_source_note=>'bad',p_created=>null,p_remainder=>1)$$,'23514',null,'Nonzero remainder without time rejected');
select throws_ok($$select pg_temp.import_note(p_note=>'bad-note',p_source_note=>'bad',p_remainder=>1000000)$$,'23514',null,'Out of range remainder rejected');
select throws_ok($$select pg_temp.import_note(p_note=>'bad-note',p_source_note=>'bad',p_updated=>1788609600000,p_updated_remainder=>1)$$,'23514',null,'Reverse nanosecond chronology rejected');
select throws_ok($$select pg_temp.import_note(p_note=>'bad-note',p_source_note=>'bad',p_principal=>'missing-principal')$$,'23503',null,'Unreconciled principal is not invented');
select throws_ok($$select pg_temp.import_note(p_note=>'bad-note',p_source_note=>'bad/source')$$,'23514',null,'Invalid source path segment rejected');
select throws_ok($$select pg_temp.import_note(p_note=>'bad-note',p_source_note=>'bad',p_bytes=>'\x'::bytea)$$,'23514',null,'Empty evidence rejected');
select is((select count(*) from public.spike_project_notes where id='bad-note'),0::bigint,'Malformed imports roll back targets');
select is((select count(*) from ledger_private.imported_project_note_sources where note_id='bad-note'),0::bigint,'Malformed imports roll back evidence');
insert into public.spike_project_notes(id,account_id,project_id,content_kind,note_text,source,revision)
  values ('preexisting-note','account-primary','note-import-project','visible','Existing','text',0);
select throws_ok($$select pg_temp.import_note(p_note=>'preexisting-note',p_source_note=>'preexisting')$$,'22000',null,'Preexisting target cannot be overwritten');
select is((select note_text from public.spike_project_notes where id='preexisting-note'),'Existing','Target collision leaves existing content intact');
update public.spike_project_notes set note_text='Later corrected content' where id='imported-note';
select throws_ok($$select pg_temp.import_note()$$,'22000',null,'Retry does not overwrite subsequent target changes');
select ok((select bool_and(to_jsonb(p)=b.projection) from public.spike_projects p join note_import_parent_before b using(id)),'Parent fields and legacy notes remain unchanged');
select throws_ok($$update ledger_private.imported_project_note_sources set source_bytes='\x01'::bytea$$,'55000',null,'Evidence update denied');
select throws_ok('delete from ledger_private.imported_project_note_sources','55000',null,'Evidence delete denied');
select throws_ok('truncate ledger_private.imported_project_note_sources','55000',null,'Evidence truncate denied');
select ok((select bool_and(not has_table_privilege(r,'ledger_private.imported_project_note_sources','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  and not has_function_privilege(r,'ledger_private.import_project_note(text,text,text,text,text,text,text,text,bigint,integer,bigint,integer,text,text,text,bytea)','EXECUTE'))
  from unnest(array['anon','authenticated','service_role']) r),'All API roles lack evidence and importer privileges');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='ledger_private.imported_project_note_sources'::regclass),'Private evidence forces RLS');
select ok((select not prosecdef and proconfig @> array['search_path=""']
  and exists(select 1 from unnest(proconfig) setting where lower(setting)='timezone=utc') from pg_proc
  where oid='ledger_private.import_project_note(text,text,text,text,text,text,text,text,bigint,integer,bigint,integer,text,text,text,bytea)'::regprocedure),'Importer uses invoker, empty search path and stable timezone');
set local role authenticated;
select throws_ok($$select ledger_private.import_project_note('a','p','n','t','mcp',null,null,null,null,null,null,null,'a','p','n','\x01'::bytea)$$,'42501',null,'Authenticated caller cannot import');
reset role;
set local role service_role;
select throws_ok($$select ledger_private.import_project_note('a','p','n','t','mcp',null,null,null,null,null,null,null,'a','p','n','\x01'::bytea)$$,'42501',null,'Service API cannot import');
reset role;
select * from finish();
rollback;
