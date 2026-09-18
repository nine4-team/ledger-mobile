begin;
select no_plan();
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('capture-item','account-primary','Chair','principal-owner');
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values('capture-item','account-primary','capture-item',1,0);
create function pg_temp.reserve_item(id text, hash text default repeat('a',64),
 account text default 'account-primary', media text default 'image/png',
 item text default 'capture-item', local_position bigint default 0,
 primary_intent boolean default true)
returns jsonb language sql security invoker as $$
 select public.spike_begin_item_attachment_upload(id,account,item,hash,12,media,'Original.png',local_position,primary_intent)
$$;
select ok(not has_table_privilege('authenticated','ledger_private.item_attachment_uploads','SELECT,INSERT,UPDATE,DELETE'),'private reservations');
select ok(not has_function_privilege('anon','public.spike_begin_item_attachment_upload(text,text,text,text,bigint,text,text,bigint,boolean)','EXECUTE'),'anonymous admission denied');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(pg_temp.reserve_item('capture-original')->>'phase','awaiting_upload','nonfinancial member can add Item image');
select is(pg_temp.reserve_item('capture-original')->>'storagePath','accounts/account-primary/attachments/capture-original/'||repeat('a',64),'exact replay retains path');
select throws_ok($$select pg_temp.reserve_item('capture-original',repeat('b',64))$$,'PT409','item_upload_identity_conflict','changed bytes denied');
select throws_ok($$select pg_temp.reserve_item('capture-foreign',repeat('a',64),'account-other')$$,'42501','item_upload_unavailable','foreign Account denied');
select throws_ok($$select pg_temp.reserve_item('capture-pdf',repeat('a',64),'account-primary','application/pdf')$$,'23514',null,'Item accepts images not PDFs');
select lives_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/capture-original/'||repeat('a',64))$$,'reserved original upload allowed');
select throws_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/unreserved/'||repeat('a',64))$$,'42501',null,'unreserved upload denied');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/capture-original/%'),1::bigint,'capturing principal reads pending bytes');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/capture-original/%'),0::bigint,'no list capability');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/capture-original/%'),0::bigint,'other member cannot read pending original');
reset role;
select is((select count(*) from ledger_private.item_attachment_uploads where id='capture-original'),1::bigint,'one reservation after replay');
select is((select count(*) from public.item_image_references where item_id='capture-item'),0::bigint,'reservation is not publication');
select ok(not has_function_privilege('authenticated','public.spike_publish_verified_item_attachment(uuid,text,text,bigint,text)','EXECUTE'),'client cannot self-verify bytes');
set local role service_role;
select throws_ok($$select public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000001','capture-original',repeat('a',64),12,'image/png')$$,'42501','item_upload_unavailable','wrong actor cannot publish');
select throws_ok($$select public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-original',repeat('b',64),12,'image/png')$$,'PT409','stored_bytes_mismatch','mismatched bytes never publish');
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-original',repeat('a',64),12,'image/png')->>'phase','applied','verified original attaches to Item');
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-original',repeat('a',64),12,'image/png')->>'revision','2','retry returns original result');
reset role;
set constraints all deferred;
select is((select expected_count from public.item_image_sets where id='capture-item'),1,'retry did not grow gallery');
select is((select count(*) from public.item_image_references where item_id='capture-item'),1::bigint,'one stable reference');
select ok((select is_primary from public.item_image_references where id='capture-original'),'first photo retains primary intent');

-- A later completion is inserted at the chosen local position and cannot take
-- primary merely because its retry races or completes after the first image.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(pg_temp.reserve_item('capture-late',repeat('b',64),'account-primary','image/jpeg','capture-item',9,false)->>'phase','awaiting_upload','later Item image reserves with placement');
select lives_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/capture-late/'||repeat('b',64))$$,'later reserved original upload allowed');
reset role;
set local role service_role;
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-late',repeat('b',64),12,'image/jpeg')->>'phase','applied','later Item image publishes');
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-late',repeat('b',64),12,'image/jpeg')->>'revision','3','later publication advances gallery revision');
reset role;
set constraints all immediate;
select is((select position from public.item_image_references where id='capture-late'),1,'later local position is clamped after first image');
select ok(not (select is_primary from public.item_image_references where id='capture-late'),'later image does not become primary');
select is((select count(*) from public.item_image_references where item_id='capture-item' and is_primary),1::bigint,'one primary after later publication');
select is(pg_temp.reserve_item('capture-middle',repeat('c',64),'account-primary','image/webp','capture-item',0,true)->>'phase','awaiting_upload','front insertion reserves');
select lives_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/capture-middle/'||repeat('c',64))$$,'front reserved original upload allowed');
reset role;
set constraints all deferred;
set local role service_role;
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-middle',repeat('c',64),12,'image/webp')->>'position','0','front insertion keeps selected order');
reset role;
set constraints all immediate;
select is((select string_agg(id,',' order by position) from public.item_image_references where item_id='capture-item'),'capture-middle,capture-original,capture-late','reference order follows positions');
select is((select count(*) from public.item_image_references where item_id='capture-item' and is_primary),1::bigint,'front insertion still leaves one primary');
set constraints all deferred;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(pg_temp.reserve_item('capture-before-full')->>'phase','awaiting_upload','reserve before concurrent gallery fills');
select lives_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/capture-before-full/'||repeat('a',64))$$,'pending original retained before publication');
reset role;
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select 'capacity-'||n,'account-primary',repeat('a',64),12,'image/png',
 'accounts/account-primary/attachments/capacity-'||n||'/'||repeat('a',64) from generate_series(1,47) n;
update public.item_image_sets set revision=5,expected_count=50 where id='capture-item';
update public.item_image_references set set_revision=5 where item_id='capture-item';
insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
select 'capacity-'||n,'account-primary','capture-item','capacity-'||n,5,n+2,false from generate_series(1,47) n;
set constraints all immediate;
set local role service_role;
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-before-full',repeat('a',64),12,'image/png')->>'errorCode','item_gallery_full','publication rechecks capacity');
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-before-full',repeat('a',64),12,'image/png')->>'phase','rejected','rejection is stable across retries');
select is(public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-original',repeat('a',64),12,'image/png')->>'revision','2','successful retry survives subsequent gallery changes');
reset role;
select is((select count(*) from public.item_image_references where item_id='capture-item'),50::bigint,'full rejection creates no extra reference');
select is((select count(*) from public.item_image_objects where id='capture-before-full'),0::bigint,'rejected original not published');
set local role authenticated;
select throws_ok($$select pg_temp.reserve_item('capture-after-full')$$,'PT409','item_gallery_full','full gallery rejects new admission');
reset role;

-- A pending consistency failure must roll back the new object, reference, set
-- revision and result together rather than leaving a partially published image.
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('capture-atomic-failure','account-primary','Atomic publication failure','principal-owner');
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values('capture-atomic-failure','account-primary','capture-atomic-failure',1,0);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(pg_temp.reserve_item('capture-atomic-failure',repeat('d',64),'account-primary','image/png','capture-atomic-failure',0,true)->>'phase','awaiting_upload','atomic-failure image reserves');
select lives_ok($$insert into storage.objects(bucket_id,name) values('ledger-attachments','accounts/account-primary/attachments/capture-atomic-failure/'||repeat('d',64))$$,'atomic-failure bytes exist');
reset role;
set constraints all deferred;
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
values('capture-corrupt-existing','account-primary',repeat('e',64),12,'image/png',
 'accounts/account-primary/attachments/capture-corrupt-existing/'||repeat('e',64));
insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
values('capture-corrupt-existing','account-primary','capture-atomic-failure','capture-corrupt-existing',1,0,true);
set local role service_role;
select throws_ok($$select public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-atomic-failure',repeat('d',64),12,'image/png')$$,'23514','Current Item image set is inconsistent','inconsistent publication rolls back');
reset role;
select is((select revision from public.item_image_sets where id='capture-atomic-failure'),1::bigint,'failed publication leaves gallery revision');
select is((select expected_count from public.item_image_sets where id='capture-atomic-failure'),0,'failed publication leaves gallery count');
select is((select count(*) from public.item_image_objects where id='capture-atomic-failure'),0::bigint,'failed publication leaves no object');
select is((select count(*) from public.item_image_references where id='capture-atomic-failure'),0::bigint,'failed publication leaves no reference');
select is((select count(*) from ledger_private.item_attachment_upload_results where upload_id='capture-atomic-failure'),0::bigint,'failed publication leaves no result');

update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select pg_temp.reserve_item('capture-original')$$,'42501','item_upload_unavailable','removed member cannot replay');
select is((select count(*) from storage.objects where name like '%/capture-original/%'),0::bigint,'removal withdraws pending bytes');
reset role;
set local role service_role;
select throws_ok($$select public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000002','capture-original',repeat('a',64),12,'image/png')$$,'42501','item_upload_unavailable','removed actor cannot replay publication');
reset role;
select * from finish();
rollback;
