-- Read already-authorized profile evidence only. No edit, upload or retention command.
-- Missing row means unknown/not migrated; a row with null logo means known absent.
create table public.spike_account_business_profiles (
  id text primary key references public.spike_accounts(id),
  account_id text not null unique references public.spike_accounts(id),
  logo_attachment_id text,
  logo_content_sha256 text,
  logo_byte_count bigint,
  logo_media_type text,
  logo_storage_path text unique,
  revision bigint not null default 1 check (revision > 0),
  check (id = account_id),
  check (num_nonnulls(logo_attachment_id, logo_content_sha256, logo_byte_count,
    logo_media_type, logo_storage_path) in (0, 5)),
  check (logo_attachment_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'),
  check (logo_content_sha256 ~ '^[0-9a-f]{64}$'),
  check (logo_byte_count > 0),
  check (logo_media_type ~ '^image/[a-z0-9][a-z0-9.+-]{0,126}$'),
  check (logo_storage_path = 'accounts/' || account_id || '/attachments/' ||
    logo_attachment_id || '/' || logo_content_sha256)
);
alter table public.spike_account_business_profiles enable row level security;
alter table public.spike_account_business_profiles force row level security;
revoke all on public.spike_account_business_profiles from public, anon, authenticated, service_role;
grant select on public.spike_account_business_profiles to authenticated;
create policy spike_account_business_profiles_select_active_member
  on public.spike_account_business_profiles for select to authenticated
  using (ledger_private.has_active_membership(account_id));

-- Immutable content path; this reference alone authorizes the exact current logo.
-- Default FK behavior deliberately does not introduce cascading deletion policy.
insert into storage.buckets(id, name, public)
values ('ledger-attachments', 'ledger-attachments', false);

create policy ledger_account_profile_logo_download
  on storage.objects for select to authenticated
  using (
    bucket_id = 'ledger-attachments'
    -- SELECT is also used for signed URL creation/listing. Permit only authenticated GET.
    and storage.operation() in ('object.get_authenticated', 'storage.object.get_authenticated')
    and exists (
      select 1 from public.spike_account_business_profiles as profile
      where profile.logo_storage_path = storage.objects.name
        and ledger_private.has_active_membership(profile.account_id)
    )
  );
