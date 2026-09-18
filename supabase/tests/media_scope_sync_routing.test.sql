begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,lifecycle,revision,
  created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
select id,'account-primary','client-existing',id,'active',1,
  '2026-09-05T12:00:00Z','2026-09-05T12:00:00Z',1788609600000,1788609600000,'principal-owner'
from (values('media-project-a'),('media-project-b')) f(id);
insert into public.spike_items(id,account_id,description,created_by_principal_id)
select id,'account-primary',id,'principal-owner' from (values('media-item-a'),('media-item-b')) f(id);
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
select id,'account-primary',id,'project','media-project-a','2026-09-18','principal-owner'
from (values('media-item-a'),('media-item-b')) f(id);
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select id,'account-primary',repeat('a',64),123,'image/jpeg','accounts/account-primary/attachments/'||id||'/'||repeat('a',64)
from (values('media-original'),('media-thumbnail')) f(id);
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
select id,'account-primary',id,1,1 from (values('media-item-a'),('media-item-b')) f(id);
insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
select id,'account-primary',id,'media-original',1,0,true from (values('media-item-a'),('media-item-b')) f(id);
set constraints all immediate;
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-a'),1::bigint,
  'one Project object for two referencing Items');
insert into public.item_card_thumbnails values('media-thumbnail-link','account-primary','media-original','media-thumbnail','item-card-300-jpeg-v1',300,200);
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-a'),2::bigint,
  'late thumbnail publication adds derivative object');
select is((select count(*) from ledger_private.media_sync_thumbnails where scope_kind='project' and scope_id='media-project-a'),1::bigint,
  'shared thumbnail link has one canonical output');
select is((select byte_count from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-a' and attachment_id='media-original'),123::bigint,
  'projection preserves original descriptor');
select is((select count(*) from ledger_private.media_sync_objects p left join public.item_image_objects o
  on o.account_id=p.account_id and o.id=p.attachment_id
  where o.id is null or row(p.content_sha256,p.byte_count,p.media_type,p.storage_path)
    is distinct from row(o.content_sha256,o.byte_count,o.media_type,o.storage_path)),0::bigint,
  'every derived descriptor has exact canonical object metadata; no orphan projection');
update public.item_image_references set sync_is_current=false,sync_project_id='spoof' where id='media-item-a';
select ok((select sync_is_current and sync_project_id='media-project-a' from public.item_image_references where id='media-item-a'),
  'routing is derived, never caller supplied');
insert into public.spike_spaces(id,account_id,scope_kind,display_name) values('media-space','account-primary','business_inventory','Media');
set constraints all deferred;
insert into public.space_media_sets values('media-space','account-primary','media-space',1,1);
insert into public.space_media_references(id,account_id,space_id,attachment_id,set_revision,position,is_primary)
  values('media-space-ref','account-primary','media-space','media-original',1,0,true);
set constraints all immediate;
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='space' and scope_id='media-space'),1::bigint,
  'Space shares immutable original without borrowing Item thumbnail');
update public.item_image_sets set revision=2,expected_count=0 where id='media-item-a';
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='item' and scope_id='media-item-a'),0::bigint,
  'new empty revision withdraws exact Item original and derivative');
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-a'),2::bigint,
  'second Item retains shared Project object and thumbnail');
select is((select count(*) from public.item_image_references where id='media-item-a'),1::bigint,'prior revision evidence retained');
update public.spike_item_placements set ended_at='2026-09-19',ended_by_principal_id='principal-owner' where id='media-item-b';
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
  values('media-moved','account-primary','media-item-b','project','media-project-b','2026-09-19','principal-owner');
select is((select sync_project_id from public.item_image_references where id='media-item-b'),'media-project-b','reference follows canonical move');
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-a'),0::bigint,
  'old Project loses final reference on move');
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-b'),2::bigint,
  'new Project receives original and derivative transactionally');
update public.item_image_sets set revision=2,expected_count=0 where id='media-item-b';
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='project' and scope_id='media-project-b'),0::bigint,
  'final Project reference withdrawal removes route');
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='space' and scope_id='media-space'),1::bigint,
  'independent Space reference retains shared original');
update public.space_media_sets set revision=2,expected_count=0 where id='media-space';
select is((select count(*) from ledger_private.media_sync_objects where scope_kind='space' and scope_id='media-space'),0::bigint,
  'Space revision withdrawal removes scope only');
select is((select count(*) from public.item_image_objects where id in ('media-original','media-thumbnail')),2::bigint,
  'no implicit byte or object deletion');
select throws_ok($$delete from public.item_image_objects where id='media-original'$$,'55000',
  'Original image object evidence is immutable','canonical deletion guard remains independent of projection foreign keys');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.spike_begin_item_attachment_upload('media-original','account-primary','media-item-a',
  repeat('a',64),123,'image/jpeg','Photo.jpg',0,false)$$,'PT409','item_upload_identity_conflict',
  'new capture cannot introduce a shared existing original outside gallery prelocking');
reset role;
select ok(not has_table_privilege('authenticated','ledger_private.media_sync_objects','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','ledger_private.media_sync_thumbnails','SELECT,INSERT,UPDATE,DELETE'),
  'no new client or service API authority');
select is((select count(*) from pg_class where oid in ('ledger_private.media_sync_objects'::regclass,
  'ledger_private.media_sync_thumbnails'::regclass) and relrowsecurity and relforcerowsecurity),2::bigint,'private projections force RLS');
select * from finish();
rollback;
