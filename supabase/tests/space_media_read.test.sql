begin;
select no_plan();
select is((select count(*) from pg_class where oid in ('public.space_media_sets'::regclass,
  'public.space_media_references'::regclass) and relrowsecurity and relforcerowsecurity),2::bigint,'Space media forces RLS');
select ok(not has_table_privilege('authenticated','public.space_media_sets','INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.space_media_references','INSERT,UPDATE,DELETE'), 'read-only API grants');
select ok(not has_table_privilege('anon','public.space_media_sets','SELECT')
  and not has_table_privilege('service_role','public.space_media_references','SELECT'), 'no anonymous or service-role catalog grant');
insert into public.spike_spaces(id,account_id,scope_kind,display_name) values
  ('space-media-a','account-primary','business_inventory','Media'),
  ('space-media-b','account-other','business_inventory','Foreign media');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) values
  ('space-media-photo','account-primary',repeat('a',64),4,'image/jpeg','accounts/account-primary/attachments/space-media-photo/'||repeat('a',64)),
  ('space-media-pdf','account-primary',repeat('b',64),4,'application/pdf','accounts/account-primary/attachments/space-media-pdf/'||repeat('b',64)),
  ('space-media-foreign','account-other',repeat('c',64),4,'image/jpeg','accounts/account-other/attachments/space-media-foreign/'||repeat('c',64));
insert into public.space_media_sets values ('space-media-set-a','account-primary','space-media-a',1,2),
  ('space-media-set-b','account-other','space-media-b',1,1);
insert into public.space_media_references values
  ('space-media-ref-a','account-primary','space-media-a','space-media-photo',1,0,true,null),
  ('space-media-ref-pdf','account-primary','space-media-a','space-media-pdf',1,1,false,'Plan.pdf'),
  ('space-media-ref-b','account-other','space-media-b','space-media-foreign',1,0,true,null);
set constraints all immediate;
select throws_ok($$insert into public.space_media_references values
  ('space-media-wrong','account-primary','space-media-a','space-media-foreign',1,2,false,null)$$,
  '23503',null,'cannot attach a foreign Account object');
select throws_ok($$update public.space_media_sets set expected_count=3 where id='space-media-set-a'$$,
  '23514','Current Space media set is inconsistent','count mismatch rejected');
select throws_ok($$update public.space_media_references set position=3 where id='space-media-ref-pdf'$$,
  '23514','Current Space media set is inconsistent','position gap rejected');
select throws_ok($$update public.space_media_references set is_primary=true where id='space-media-ref-pdf'$$,
  '23505',null,'second primary rejected');
select throws_ok($$update public.space_media_sets set id='changed' where id='space-media-set-a'$$,
  '55000','Space media parent identity is immutable','stable parent identity');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.space_media_sets where id like 'space-media-%'),1::bigint,'restricted member sees own Space set');
select is((select count(*) from public.space_media_references where id like 'space-media-%'),2::bigint,'restricted member sees own image and PDF');
select is((select count(*) from public.item_image_objects where id like 'space-media-%'),2::bigint,'shared object policy allows only visible Space objects');
reset role;
update public.spike_spaces set lifecycle='archived' where id='space-media-a';
set local role authenticated;
select is((select count(*) from public.space_media_sets where id='space-media-set-a'),0::bigint,'unreferenced archived Space withdraws catalog');
select is((select count(*) from public.item_image_objects where id in ('space-media-photo','space-media-pdf')),0::bigint,'archived inaccessible parent withdraws bytes');
reset role;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
  values ('space-media-item','account-primary','Archived parent reference','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,space_id,started_at,started_by_principal_id)
  values ('space-media-placement','account-primary','space-media-item','business_inventory','space-media-a','2026-09-18','principal-owner');
set local role authenticated;
select is((select count(*) from public.space_media_sets where id='space-media-set-a'),1::bigint,'current physical parent remains readable when archived');
reset role;
update public.space_media_sets set revision=2,expected_count=0 where id='space-media-set-a';
set local role authenticated;
select is((select count(*) from public.space_media_references where space_id='space-media-a'),0::bigint,'old revision relationships are not current');
select is((select count(*) from public.item_image_objects where id in ('space-media-photo','space-media-pdf')),0::bigint,'old revision does not grant byte access');
reset role;
update public.spike_account_memberships set state='removed'
  where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is((select count(*) from public.space_media_sets where id='space-media-set-a'),0::bigint,'removed member loses catalog');
select * from finish();
rollback;
