begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('gallery-item','account-primary','Gallery','principal-owner'),
 ('gallery-empty','account-primary','Empty','principal-owner'),
 ('gallery-foreign','account-other','Foreign','principal-other');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
select id,account,repeat('a',64),123,'image/png','accounts/'||account||'/attachments/'||id||'/'||repeat('a',64)
from (values ('gallery-object','account-primary'),('gallery-orphan','account-primary'),('gallery-other-object','account-other')) f(id,account);
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values ('gallery-item','account-primary','gallery-item',1,1),('gallery-empty','account-primary','gallery-empty',1,0),
 ('gallery-foreign','account-other','gallery-foreign',1,1);
insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
values ('gallery-ref','account-primary','gallery-item','gallery-object',1,0,true),
 ('gallery-other-ref','account-other','gallery-foreign','gallery-other-object',1,0,true);
set constraints all immediate;
select throws_ok($$update public.item_image_objects set byte_count=124 where id='gallery-object'$$,
 '55000',null,'Original identity and bytes metadata cannot mutate');
select throws_ok($$delete from public.item_image_objects where id='gallery-orphan'$$,
 '55000',null,'No implicit object purge');
select throws_ok($$update public.item_image_sets set expected_count=2 where id='gallery-item'$$,
 '23514',null,'Current marker must match exact reference count');
select throws_ok($$update public.item_image_references set position=2 where id='gallery-ref'$$,
 '23514',null,'Current order must be contiguous from zero');
select throws_ok($$insert into public.item_image_references values ('gallery-wrong','account-primary','gallery-empty','gallery-other-object',1,0,true)$$,
 '23503',null,'Composite foreign key prevents cross-Account object sharing');
select throws_ok($$update public.item_image_references set item_id='gallery-empty' where id='gallery-ref'$$,
 '55000',null,'Reference identity cannot move to another parent');
select throws_ok($$set constraints all deferred;
 update public.item_image_sets set expected_count=2 where id='gallery-item';
 insert into public.item_image_references values ('gallery-second','account-primary','gallery-item','gallery-orphan',1,1,true);
 set constraints all immediate$$,'23505',null,'Multiple primary references rejected by unique index');
insert into storage.objects(bucket_id,name)
select 'ledger-attachments',storage_path from public.item_image_objects where id like 'gallery-%';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select expected_count from public.item_image_sets where id='gallery-empty'),0,'Explicit empty marker readable');
select is((select count(*) from public.item_image_references where item_id='gallery-item'),1::bigint,'Member reads exact current references');
select is((select count(*) from public.item_image_objects where id like 'gallery-%'),1::bigint,'Only current referenced same-Account object readable');
select is((select count(*) from public.item_image_sets where id='gallery-foreign'),0::bigint,'Foreign catalog denied');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where name like '%/gallery-%'),1::bigint,'Authenticated GET only exact authorized current image');
select set_config('storage.operation','storage.object.sign',true);
select is((select count(*) from storage.objects where name like '%/gallery-%'),0::bigint,'No signed image URL capability');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where name like '%/gallery-%'),0::bigint,'No image listing capability');
select throws_ok($$update public.item_image_references set is_primary=false where id='gallery-ref'$$,
 '42501',null,'Read-only gallery grants no primary edit');
select throws_ok($$delete from public.item_image_references where id='gallery-ref'$$,
 '42501',null,'Read-only gallery grants no detach');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from public.item_image_sets where id like 'gallery-%'),0::bigint,'Same JWT loses catalog on removal');
select is((select count(*) from storage.objects where name like '%/gallery-%'),0::bigint,'Same JWT loses image bytes on removal');
reset role;
set local role anon;
select throws_ok('select * from public.item_image_sets','42501',null,'Anonymous catalog ungranted');
reset role;
set constraints all deferred;
update public.item_image_sets set revision=2,expected_count=1 where id='gallery-empty';
insert into public.item_image_references values ('gallery-shared','account-primary','gallery-empty','gallery-object',2,0,true);
set constraints all immediate;
select is((select count(*) from public.item_image_references where attachment_id='gallery-object'),2::bigint,
 'One immutable original may serve independent Item references');
select * from finish();
rollback;
