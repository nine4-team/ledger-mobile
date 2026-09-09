begin;
set local search_path=public,extensions;
select no_plan();
-- Convenience fixture only; publication remains an explicit metadata contract.
create function pg_temp.publish_thumbnail(
 original_id text default 'publication-original', derivative_id text default 'publication-small',
 link_id text default 'publication-link', width integer default 300,
 original_sha text default repeat('a',64), derivative_sha text default repeat('b',64),
 derivative_type text default 'image/jpeg', recipe text default 'item-card-300-jpeg-v1',
 account text default 'account-primary', original_bytes bigint default 123,
 original_type text default 'image/jpeg', original_path text default null,
 derivative_bytes bigint default 321, derivative_path text default null
) returns text language sql security invoker set search_path='' as $$
 select ledger_private.publish_item_card_thumbnail(
 account,original_id,original_sha,original_bytes,original_type,
 coalesce(original_path,'accounts/'||account||'/attachments/'||original_id||'/'||repeat('a',64)),
 derivative_id,derivative_sha,derivative_bytes,derivative_type,
 coalesce(derivative_path,'accounts/'||account||'/attachments/'||derivative_id||'/'||derivative_sha),
 link_id,recipe,width,200);
$$;
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select id,'account-primary',repeat('a',64),123,'image/jpeg',
 'accounts/account-primary/attachments/'||id||'/'||repeat('a',64)
from (values ('publication-original'),('publication-other-original'),('publication-third-original')) f(id);
select is(pg_temp.publish_thumbnail(),'publication-link','Trusted publication returns exact link ID');
select is(pg_temp.publish_thumbnail(),'publication-link','Exact publication replay is idempotent');
select is((select count(*) from public.item_image_objects where id='publication-small'),1::bigint,
 'Replay does not duplicate derivative object');
select is((select count(*) from public.item_card_thumbnails where id='publication-link'),1::bigint,
 'Replay does not duplicate link');
select is((select row(account_id,content_sha256,byte_count,media_type,storage_path)::text
 from public.item_image_objects where id='publication-small'),
 row('account-primary',repeat('b',64),321,'image/jpeg',
 'accounts/account-primary/attachments/publication-small/'||repeat('b',64))::text,
 'Published derivative retains exact immutable metadata');
select is((select count(*) from storage.objects where name like '%/publication-%'),0::bigint,
 'Database publication does not manufacture uploaded Storage evidence');
select throws_ok($$select pg_temp.publish_thumbnail(original_sha=>repeat('c',64))$$,
 '22000',null,'Replay checks original digest before accepting existing link');
select throws_ok($$select pg_temp.publish_thumbnail(original_bytes=>124)$$,
 '22000',null,'Original byte count must match exactly');
select throws_ok($$select pg_temp.publish_thumbnail(original_type=>'image/png')$$,
 '22000',null,'Original media type must match exactly');
select throws_ok($$select pg_temp.publish_thumbnail(original_path=>'wrong/path')$$,
 '22000',null,'Original storage identity must match exactly');
select throws_ok($$select pg_temp.publish_thumbnail(account=>'account-other')$$,
 '23503',null,'Publication cannot borrow original from another Account');
select throws_ok($$select pg_temp.publish_thumbnail(original_id=>'publication-missing')$$,
 '23503',null,'Publication requires an existing original');
select throws_ok($$select pg_temp.publish_thumbnail(width=>299)$$,
 '22000',null,'Same recipe cannot replace dimensions');
select throws_ok($$select pg_temp.publish_thumbnail(link_id=>'publication-replay-other-id')$$,
 '22000',null,'Replay cannot replace link identity');
select throws_ok($$select pg_temp.publish_thumbnail(derivative_sha=>repeat('c',64))$$,
 '22000',null,'Replay cannot replace derivative digest');
select throws_ok($$select pg_temp.publish_thumbnail(derivative_id=>'publication-conflict-small',link_id=>'publication-conflict')$$,
 '22000',null,'Same recipe cannot publish another derivative');
select is((select count(*) from public.item_image_objects where id='publication-conflict-small'),0::bigint,
 'Recipe conflict inserts no orphan object');
select throws_ok($$select pg_temp.publish_thumbnail(original_id=>'publication-other-original',
 derivative_id=>'publication-small',link_id=>'publication-object-conflict',derivative_bytes=>322)$$,
 '22000',null,'Preexisting derivative ID requires exact object metadata');
select is((select count(*) from public.item_card_thumbnails where id='publication-object-conflict'),0::bigint,
 'Object conflict inserts no link');
select throws_ok($$select pg_temp.publish_thumbnail(original_id=>'publication-other-original',
 derivative_id=>'publication-link-conflict-small')$$,
 '22000',null,'Global link-ID conflict rejects publication');
select is((select count(*) from public.item_image_objects where id='publication-link-conflict-small'),0::bigint,
 'Link-ID conflict rolls back newly inserted object');
select throws_ok($$select pg_temp.publish_thumbnail(original_id=>'publication-other-original',
 derivative_id=>'publication-invalid-small',link_id=>'publication-invalid',width=>301)$$,
 '23514',null,'New publication rejects invalid recipe dimensions');
select is((select count(*) from public.item_image_objects where id='publication-invalid-small'),0::bigint,
 'Invalid link rolls back newly inserted object');
select throws_ok($$select pg_temp.publish_thumbnail(original_id=>'publication-other-original',
 derivative_id=>'publication-png-small',link_id=>'publication-png',derivative_type=>'image/png')$$,
 '23514',null,'New publication requires JPEG metadata');
select is((select count(*) from public.item_image_objects where id='publication-png-small'),0::bigint,
 'Wrong recipe media type inserts no orphan object');
select throws_ok($$select pg_temp.publish_thumbnail(original_id=>'publication-other-original',
 derivative_id=>'publication-path-small',link_id=>'publication-path',derivative_path=>'wrong/path')$$,
 '23514',null,'Derivative path remains bound to Account ID, object ID and hash');
select is(pg_temp.publish_thumbnail(original_id=>'publication-other-original',link_id=>'publication-reused'),
 'publication-reused','Exact existing immutable derivative can be reused for another original');
select is((select count(*) from public.item_image_objects where id='publication-small'),1::bigint,
 'Reusing exact object creates no duplicate bytes metadata');
select ok(not p.prosecdef,'Publisher is security invoker') from pg_proc p
 where p.oid='ledger_private.publish_item_card_thumbnail(text,text,text,bigint,text,text,text,text,bigint,text,text,text,text,integer,integer)'::regprocedure;
select ok(not has_function_privilege(role_name,
 'ledger_private.publish_item_card_thumbnail(text,text,text,bigint,text,text,text,text,bigint,text,text,text,text,integer,integer)',
 'EXECUTE'),role_name||' cannot execute trusted publisher')
from (values ('anon'),('authenticated'),('service_role')) r(role_name);
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('thumb-item','account-primary','Thumbnail','principal-owner'),
 ('thumb-other','account-other','Foreign','principal-other');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select id,account,repeat('a',64),123,'image/jpeg',
 'accounts/'||account||'/attachments/'||id||'/'||repeat('a',64)
from (values ('thumb-original','account-primary'),('thumb-small','account-primary'),
 ('thumb-orphan','account-primary'),('thumb-orphan-small','account-primary'),
 ('thumb-foreign','account-other'),('thumb-foreign-small','account-other')) f(id,account);
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values ('thumb-item','account-primary','thumb-item',1,1),
 ('thumb-other','account-other','thumb-other',1,1);
insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
values ('thumb-ref','account-primary','thumb-item','thumb-original',1,0,true),
 ('thumb-other-ref','account-other','thumb-other','thumb-foreign',1,0,true);
insert into public.item_card_thumbnails values
 ('thumb-link','account-primary','thumb-original','thumb-small','item-card-300-jpeg-v1',300,200),
 ('thumb-orphan-link','account-primary','thumb-orphan','thumb-orphan-small','item-card-300-jpeg-v1',200,100),
 ('thumb-foreign-link','account-other','thumb-foreign','thumb-foreign-small','item-card-300-jpeg-v1',300,200);
set constraints all immediate;
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-cross','account-primary','thumb-orphan-small','thumb-foreign-small','item-card-300-jpeg-v1',100,100)$$,
 '23503',null,'Cannot borrow another Account derivative');
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-cross-source','account-primary','thumb-foreign','thumb-small','item-card-300-jpeg-v1',100,100)$$,
 '23503',null,'Cannot borrow another Account original');
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-self','account-primary','thumb-small','thumb-small','item-card-300-jpeg-v1',100,100)$$,
 '23514',null,'Original cannot masquerade as its own thumbnail');
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-duplicate','account-primary','thumb-original','thumb-orphan-small','item-card-300-jpeg-v1',100,100)$$,
 '23505',null,'One derivative per immutable original and recipe');
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-big','account-primary','thumb-small','thumb-original','item-card-300-jpeg-v1',301,100)$$,
 '23514',null,'Thumbnail dimensions bounded');
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-recipe','account-primary','thumb-small','thumb-original','unknown',100,100)$$,
 '23514',null,'Unknown recipe rejected');
insert into public.item_image_objects values ('thumb-png','account-primary',repeat('a',64),123,'image/png',
 'accounts/account-primary/attachments/thumb-png/'||repeat('a',64));
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-wrong-format','account-primary','thumb-small','thumb-png','item-card-300-jpeg-v1',100,100)$$,
 '23514',null,'JPEG recipe cannot point to PNG metadata');
select throws_ok($$update public.item_card_thumbnails set thumbnail_attachment_id='thumb-orphan-small' where id='thumb-link'$$,
 '55000',null,'Derivative identity immutable');
select throws_ok($$delete from public.item_card_thumbnails where id='thumb-link'$$,
 '55000',null,'No implicit derivative purge');
select throws_ok('truncate public.item_card_thumbnails','55000',null,'No truncate bypass');
insert into storage.objects(bucket_id,name)
select 'ledger-attachments',storage_path from public.item_image_objects where id like 'thumb-%';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.item_card_thumbnails where id like 'thumb-%'),1::bigint,
 'Only live same-Account original exposes its derivative link');
select is((select count(*) from public.item_image_objects where id like 'thumb-%'),2::bigint,
 'Original and small bytes metadata readable without recursive RLS');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/thumb-%'),2::bigint,
 'GET admits original and derivative, not foreign or orphan bytes');
select set_config('storage.operation','storage.object.sign',true);
select is((select count(*) from storage.objects where name like '%/thumb-%'),0::bigint,'No signed URLs');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/thumb-%'),0::bigint,'No bucket listing');
select throws_ok($$insert into public.item_card_thumbnails values
 ('thumb-forged','account-primary','thumb-small','thumb-orphan','item-card-300-jpeg-v1',100,100)$$,
 '42501',null,'Readers cannot publish or forge derivative authority');
select throws_ok($$update public.item_card_thumbnails set pixel_width=200 where id='thumb-link'$$,
 '42501',null,'Readers cannot rewrite metadata');
select throws_ok($$delete from public.item_card_thumbnails where id='thumb-link'$$,
 '42501',null,'Readers cannot remove link');
reset role;
-- Old references remain as evidence but must no longer authorize bytes.
update public.item_image_sets set revision=2,expected_count=0 where id='thumb-item';
set local role authenticated;
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from public.item_card_thumbnails where id like 'thumb-%'),0::bigint,'Old reference does not authorize derivative');
select is((select count(*) from public.item_image_objects where id like 'thumb-%'),0::bigint,'Old reference loses both objects');
select is((select count(*) from storage.objects where name like '%/thumb-%'),0::bigint,'Old reference loses both GET paths');
reset role;
set constraints all deferred;
update public.item_image_sets set revision=3,expected_count=1 where id='thumb-item';
insert into public.item_image_references values ('thumb-current','account-primary','thumb-item','thumb-original',3,0,true);
set constraints all immediate;
set local role authenticated;
select is((select count(*) from public.item_card_thumbnails where id like 'thumb-%'),1::bigint,'Reattached original reuses explicit immutable derivative');
reset role;
update public.spike_account_memberships set state='removed'
 where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is((select count(*) from public.item_card_thumbnails where id like 'thumb-%'),0::bigint,'Same JWT loses links after removal');
select is((select count(*) from storage.objects where name like '%/thumb-%'),0::bigint,'Same JWT loses bytes after removal');
reset role;
set local role anon;
select throws_ok('select * from public.item_card_thumbnails','42501',null,'Anonymous access ungranted');
reset role;
select * from finish();
rollback;
