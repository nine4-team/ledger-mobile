begin;

create table public.transaction_attachment_upload_results (
 upload_id text primary key references public.transaction_attachment_uploads(id),
 account_id text not null,
 principal_id text not null references public.spike_principals(id),
 transaction_id text not null,
 section text not null check(section in ('receipts','other')),
 phase text not null check(phase in ('applied','rejected')),
 result_code text,
 error_code text,
 reference_revision bigint check(reference_revision>0),
 reference_position integer check(reference_position>=0),
 completed_at timestamptz not null default clock_timestamp(),
 foreign key(account_id,transaction_id,section)
   references public.transaction_attachment_sets(account_id,transaction_id,section),
 check((phase='applied' and result_code='attachment_published' and error_code is null
        and reference_revision is not null and reference_position is not null)
    or (phase='rejected' and result_code is null and error_code is not null
        and reference_revision is null and reference_position is null))
);
alter table public.transaction_attachment_upload_results enable row level security;
alter table public.transaction_attachment_upload_results force row level security;
revoke all on public.transaction_attachment_upload_results from public,anon,authenticated,service_role;
grant select on public.transaction_attachment_upload_results to authenticated;
create policy transaction_attachment_upload_results_read on public.transaction_attachment_upload_results
 for select to authenticated using (
 principal_id=(select ledger_private.current_principal_id())
 and (select ledger_private.has_active_membership(account_id))
 and exists(select 1 from public.spike_transactions t
   where t.account_id=transaction_attachment_upload_results.account_id
     and t.id=transaction_attachment_upload_results.transaction_id)
);

create function ledger_private.reject_transaction_attachment_upload_result_change()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 raise exception using errcode='55000',message='Attachment upload result is immutable';
end;
$$;
revoke all on function ledger_private.reject_transaction_attachment_upload_result_change()
 from public,anon,authenticated,service_role;
create trigger transaction_attachment_upload_results_immutable before update or delete
 on public.transaction_attachment_upload_results for each row
 execute function ledger_private.reject_transaction_attachment_upload_result_change();
create trigger transaction_attachment_upload_results_no_truncate before truncate
 on public.transaction_attachment_upload_results for each statement
 execute function ledger_private.reject_transaction_attachment_upload_result_change();

-- These existing functions are trigger-only and have no API EXECUTE grant.
-- Publication enters through a service-only definer; its derived routing and
-- deferred consistency checks must retain that authority inside the trigger.
alter function ledger_private.derive_transaction_sync_scope() security definer;
alter function ledger_private.derive_transaction_attachment_sync_reference() security definer;
alter function ledger_private.propagate_transaction_attachment_sync_marker() security definer;
alter function ledger_private.check_transaction_attachment_set() security definer;

-- Called only by the authenticated Edge verifier after it has downloaded and
-- hashed the immutable object. Every user and parent authorization check is
-- repeated here; possession of an upload ID is never publication authority.
create function public.spike_publish_verified_transaction_attachment(
 p_auth_user_id uuid,p_upload_id text,p_observed_sha256 text,
 p_observed_byte_count bigint,p_observed_media_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 upload public.transaction_attachment_uploads;
 outcome public.transaction_attachment_upload_results;
 marker public.transaction_attachment_sets;
 actor text;
 allowed boolean;
 rejection text;
 new_revision bigint;
 target_position integer;
 stored public.item_image_objects;
 existing_reference public.transaction_attachment_references;
begin
 select id into actor from public.spike_principals where auth_user_id=p_auth_user_id;
 if actor is null then raise exception using errcode='42501',message='attachment_upload_unavailable'; end if;
 select * into outcome from public.transaction_attachment_upload_results
  where upload_id=p_upload_id and principal_id=actor;
 if found then return to_jsonb(outcome); end if;

 select * into upload from public.transaction_attachment_uploads where id=p_upload_id for update;
 if not found then raise exception using errcode='42501',message='attachment_upload_unavailable'; end if;
 if actor is distinct from upload.principal_id then
   raise exception using errcode='42501',message='attachment_upload_unavailable';
 end if;

 -- A concurrent verifier can finish while this call waits for the upload lock.
 -- Re-read its immutable result before checking capacity or publishing again.
 select * into outcome from public.transaction_attachment_upload_results
  where upload_id=upload.id and principal_id=actor;
 if found then return to_jsonb(outcome); end if;

 select exists(
   select 1 from public.spike_account_memberships membership
   join public.spike_transactions transaction on transaction.account_id=membership.account_id
     and transaction.id=upload.transaction_id
   where membership.account_id=upload.account_id and membership.principal_id=actor
     and membership.state='active' and (
       (transaction.origin='firebase_client_payment' and membership.financial_access='full')
       or (transaction.origin='vendor_payment' and exists(
         select 1 from public.spike_budget_categories category
         where category.account_id=transaction.account_id and category.id=transaction.category_id
           and (category.visibility_class='ordinary' or membership.financial_access='full')
       ))
     )
 ) into allowed;
 if not allowed then rejection := 'attachment_access_withdrawn'; end if;

 if rejection is null and row(p_observed_sha256,p_observed_byte_count,p_observed_media_type)
    is distinct from row(upload.content_sha256,upload.byte_count,upload.media_type) then
   rejection := 'stored_bytes_mismatch';
 end if;
 if rejection is null and not exists(
   select 1 from storage.objects object where object.bucket_id='ledger-attachments'
     and object.name=upload.storage_path
 ) then
   raise sqlstate 'PT409' using message='attachment_upload_incomplete';
 end if;

 if rejection is null then
   select * into marker from public.transaction_attachment_sets
    where account_id=upload.account_id and transaction_id=upload.transaction_id
      and section=upload.section for update;
   if not found then rejection := 'attachment_parent_missing';
   elsif marker.expected_count>=50 then rejection := 'attachment_section_full';
   end if;
 end if;

 if rejection is null then
   select * into stored from public.item_image_objects where id=upload.id;
   if found and row(stored.account_id,stored.content_sha256,stored.byte_count,
       stored.media_type,stored.storage_path) is distinct from
       row(upload.account_id,upload.content_sha256,upload.byte_count,
       upload.media_type,upload.storage_path) then
     rejection := 'attachment_identity_conflict';
   end if;
 end if;

 if rejection is null then
   select * into existing_reference from public.transaction_attachment_references where id=upload.id;
   if found then
     if row(existing_reference.account_id,existing_reference.transaction_id,
       existing_reference.section,existing_reference.attachment_id) is distinct from
       row(upload.account_id,upload.transaction_id,upload.section,upload.id) then
       rejection := 'attachment_identity_conflict';
     else
       new_revision := existing_reference.set_revision;
       target_position := existing_reference.position;
     end if;
   end if;
 end if;

 if rejection is null and existing_reference.id is null then
   if stored.id is null then
     insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
     values(upload.id,upload.account_id,upload.content_sha256,upload.byte_count,
       upload.media_type,upload.storage_path);
   end if;
   new_revision := marker.revision+1;
   target_position := least(upload.local_position::integer,marker.expected_count);
   update public.transaction_attachment_sets set revision=new_revision,
     expected_count=expected_count+1 where id=marker.id;
   update public.transaction_attachment_references
     set set_revision=new_revision,
       position=position+case when position>=target_position then 1 else 0 end
     where account_id=upload.account_id and transaction_id=upload.transaction_id
       and section=upload.section and set_revision=marker.revision;
   insert into public.transaction_attachment_references(id,account_id,transaction_id,section,
     attachment_id,set_revision,position,is_primary,file_name)
   values(upload.id,upload.account_id,upload.transaction_id,upload.section,upload.id,
     new_revision,target_position,marker.expected_count=0 and upload.make_primary_if_empty,
     upload.file_name);
 end if;

 insert into public.transaction_attachment_upload_results(upload_id,account_id,principal_id,
   transaction_id,section,phase,result_code,error_code,reference_revision,reference_position)
 values(upload.id,upload.account_id,upload.principal_id,upload.transaction_id,upload.section,
   case when rejection is null then 'applied' else 'rejected' end,
   case when rejection is null then 'attachment_published' else null end,rejection,
   case when rejection is null then new_revision else null end,
   case when rejection is null then target_position else null end)
 returning * into outcome;
 return to_jsonb(outcome);
end;
$$;
revoke all on function public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)
 from public,anon,authenticated,service_role;
grant execute on function public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)
 to service_role;

commit;
