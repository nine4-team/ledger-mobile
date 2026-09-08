begin;
set local search_path=public,extensions;
select no_plan();

insert into public.spike_account_business_profiles
  (id,account_id,logo_attachment_id,logo_content_sha256,logo_byte_count,logo_media_type,logo_storage_path)
values
  ('account-primary','account-primary','logo-primary',repeat('a',64),9007199254740993,'image/png',
    'accounts/account-primary/attachments/logo-primary/'||repeat('a',64)),
  ('account-other','account-other','logo-other',repeat('b',64),12,'image/jpeg',
    'accounts/account-other/attachments/logo-other/'||repeat('b',64));
insert into public.spike_accounts(id,display_name) values ('profile-absent','Known no logo'),('profile-unknown','Unknown evidence');
insert into public.spike_account_memberships(account_id,principal_id,role,state)
values ('profile-absent','principal-restricted','employee','active'),('profile-unknown','principal-restricted','employee','active');
insert into public.spike_account_business_profiles(id,account_id) values ('profile-absent','profile-absent');
-- Object metadata is sufficient to falsify Storage RLS; no hosted bytes are uploaded.
insert into storage.objects(bucket_id,name) values
 ('ledger-attachments','accounts/account-primary/attachments/logo-primary/'||repeat('a',64)),
 ('ledger-attachments','accounts/account-primary/attachments/logo-primary/'||repeat('c',64)),
 ('ledger-attachments','accounts/account-other/attachments/logo-other/'||repeat('b',64));
select is((select public from storage.buckets where id='ledger-attachments'),false,'Logo bucket is private');
select throws_ok($$update public.spike_account_business_profiles set logo_media_type=null where id='account-primary'$$,'23514',null,'Partial logo reference rejected');
select throws_ok($$update public.spike_account_business_profiles set logo_byte_count=0 where id='account-primary'$$,'23514',null,'Empty byte evidence rejected');
select throws_ok($$update public.spike_account_business_profiles set logo_storage_path='accounts/account-other/attachments/logo-other/'||repeat('b',64) where id='account-primary'$$,'23514',null,'Reference cannot point into another Account');
select throws_ok($$update public.spike_account_business_profiles set logo_attachment_id='../escape' where id='account-primary'$$,'23514',null,'Path traversal attachment identity rejected');
select throws_ok($$update public.spike_account_business_profiles set revision=0 where id='account-primary'$$,'23514',null,'Revision must be positive');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","user_metadata":{"account_id":"account-other","role":"owner"}}',true);
select is((select logo_byte_count::text from public.spike_account_business_profiles where id='account-primary'),'9007199254740993','Active restricted member reads exact byte count');
select is((select count(*) from public.spike_account_business_profiles where id='account-other'),0::bigint,'User-editable claims do not grant another Account');
select is((select count(*) from public.spike_account_business_profiles where id='profile-absent' and logo_attachment_id is null),1::bigint,'Known absent logo is explicit');
select is((select count(*) from public.spike_account_business_profiles where id='profile-unknown'),0::bigint,'Unmigrated profile is not fabricated as absent');
select throws_ok($$update public.spike_account_business_profiles set revision=2 where id='account-primary'$$,'42501',null,'Member has no profile update grant');
select throws_ok($$delete from public.spike_account_business_profiles where id='account-primary'$$,'42501',null,'Member has no profile deletion grant');
select throws_ok($$insert into public.spike_account_business_profiles(id,account_id) values ('profile-unknown','profile-unknown')$$,'42501',null,'Member has no profile creation grant');
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),1::bigint,'Authenticated GET exposes only exact current authorized logo');
select is((select count(*) from storage.objects where name='accounts/account-primary/attachments/logo-primary/'||repeat('c',64)),0::bigint,'Superseded or orphan bytes are not readable');
select is((select count(*) from storage.objects where name='accounts/account-other/attachments/logo-other/'||repeat('b',64)),0::bigint,'Cross-Account object is denied');
select set_config('storage.operation','storage.object.sign',true);
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),0::bigint,'Signed URL creation has no read policy');
select set_config('storage.operation','storage.object.list',true);
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),0::bigint,'Bucket listing has no read policy');
select set_config('storage.operation','',true);
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),0::bigint,'Unspecified Storage operations fail closed');
select set_config('storage.operation','storage.object.upload',true);
select throws_ok($$insert into storage.objects(bucket_id,name) values ('ledger-attachments','unauthorized-upload')$$,'42501',null,'No upload policy');
-- UPDATE/DELETE silently affect zero rows under the existing Storage table grants.
with changed as (update storage.objects set name='unauthorized-replacement' where bucket_id='ledger-attachments' returning id)
select is(count(*),0::bigint,'No replacement policy') from changed;
-- Match the Storage API transaction flag so this checks RLS, not direct-SQL protection.
select set_config('storage.allow_delete_query','true',true);
with removed as (delete from storage.objects where bucket_id='ledger-attachments' returning id)
select is(count(*),0::bigint,'No object deletion policy') from removed;
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('storage.operation','storage.object.get_authenticated',true);
select is((select count(*) from public.spike_account_business_profiles where id='account-primary'),0::bigint,'Same JWT loses profile after membership removal');
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),0::bigint,'Same JWT loses logo after membership removal');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.spike_account_business_profiles where id='account-primary'),1::bigint,'Owner retains profile access');
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),1::bigint,'Owner retains exact current logo access');
select throws_ok($$update public.spike_account_business_profiles set revision=2 where id='account-primary'$$,'42501',null,'Owner profile editing also remains gated');
reset role;
set local role anon;
select throws_ok('select * from public.spike_account_business_profiles','42501',null,'Anonymous profile reads denied');
select is((select count(*) from storage.objects where bucket_id='ledger-attachments'),0::bigint,'Anonymous logo reads denied');
reset role;
set local role service_role;
select throws_ok('select * from public.spike_account_business_profiles','42501',null,'API service role profile reads ungranted');
reset role;
select * from finish();
rollback;
