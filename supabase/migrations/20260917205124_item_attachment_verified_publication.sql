create table ledger_private.item_attachment_upload_results (
 upload_id text primary key references ledger_private.item_attachment_uploads(id),
 result jsonb not null,
 completed_at timestamptz not null default clock_timestamp()
);
alter table ledger_private.item_attachment_upload_results enable row level security;
alter table ledger_private.item_attachment_upload_results force row level security;
revoke all on ledger_private.item_attachment_upload_results from public,anon,authenticated,service_role;

create function ledger_private.read_item_attachment_upload(p_upload_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u ledger_private.item_attachment_uploads;
begin
 select * into u from ledger_private.item_attachment_uploads where id=p_upload_id;
 if not found or not ledger_private.can_use_item_attachment_upload(u.storage_path) then
  raise sqlstate '42501' using message='item_upload_unavailable';
 end if;
 return to_jsonb(u)||jsonb_build_object('byte_count',u.byte_count::text);
end;
$$;
revoke all on function ledger_private.read_item_attachment_upload(text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_item_attachment_upload(text) to authenticated;
create function public.spike_read_item_attachment_upload(p_upload_id text)
returns jsonb language sql security invoker set search_path='' as $$
 select ledger_private.read_item_attachment_upload(p_upload_id)
$$;
revoke all on function public.spike_read_item_attachment_upload(text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_item_attachment_upload(text) to authenticated;

create function ledger_private.publish_verified_item_attachment(
 p_auth_user_id uuid,p_upload_id text,p_observed_sha256 text,p_observed_byte_count bigint,p_observed_media_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare u ledger_private.item_attachment_uploads; marker public.item_image_sets;
 stored public.item_image_objects; existing public.item_image_references;
 result jsonb; rejection text; new_revision bigint; target_position integer;
begin
 select upload.* into u from ledger_private.item_attachment_uploads upload
 join public.spike_principals actor on actor.id=upload.principal_id and actor.auth_user_id=p_auth_user_id
 where upload.id=p_upload_id;
 if not found then raise sqlstate '42501' using message='item_upload_unavailable'; end if;
 -- Same membership/Item/upload lock order as admission. Revocation must also
 -- prevent a previously successful request from becoming a read capability.
 perform 1 from public.spike_account_memberships where account_id=u.account_id and principal_id=u.principal_id
  and state='active' for share;
 if not found then raise sqlstate '42501' using message='item_upload_unavailable'; end if;
 perform 1 from public.spike_items where account_id=u.account_id and id=u.item_id for share;
 if not found then raise sqlstate '42501' using message='item_upload_unavailable'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_upload_id,0));
 if row(p_observed_sha256,p_observed_byte_count,p_observed_media_type)
  is distinct from row(u.content_sha256,u.byte_count,u.media_type) then
  raise sqlstate 'PT409' using message='stored_bytes_mismatch';
 end if;
 select r.result into result from ledger_private.item_attachment_upload_results r where upload_id=u.id;
 if found then return result; end if;
 if not exists(select 1 from storage.objects where bucket_id='ledger-attachments' and name=u.storage_path) then
  raise sqlstate 'PT409' using message='attachment_upload_incomplete';
 end if;
 select * into marker from public.item_image_sets where account_id=u.account_id and item_id=u.item_id for update;
 if not found then rejection:='item_images_unknown';
 elsif marker.expected_count>=50 then rejection:='item_gallery_full'; end if;
 select * into stored from public.item_image_objects where id=u.id;
 if found and row(stored.account_id,stored.content_sha256,stored.byte_count,stored.media_type,stored.storage_path)
  is distinct from row(u.account_id,u.content_sha256,u.byte_count,u.media_type,u.storage_path) then
  rejection:='attachment_identity_conflict';
 end if;
 select * into existing from public.item_image_references where id=u.id;
 if found then rejection:='attachment_identity_conflict'; end if;
 if rejection is null then
  if stored.id is null then
   insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
   values(u.id,u.account_id,u.content_sha256,u.byte_count,u.media_type,u.storage_path);
  end if;
  new_revision:=marker.revision+1;
  target_position:=least(u.local_position,marker.expected_count::bigint)::integer;
  update public.item_image_sets set revision=new_revision,expected_count=expected_count+1 where id=marker.id;
  update public.item_image_references set set_revision=new_revision,
   position=position+case when position>=target_position then 1 else 0 end
   where account_id=u.account_id and item_id=u.item_id and set_revision=marker.revision;
  insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
   values(u.id,u.account_id,u.item_id,u.id,new_revision,target_position,
    u.make_primary_if_empty and not exists(select 1 from public.item_image_references
      where account_id=u.account_id and item_id=u.item_id and is_primary));
  -- Deferred constraint triggers otherwise run after this definer returns,
  -- under the verifier's service_role (which deliberately cannot mutate the
  -- gallery tables). Check the completed atomic publication here, retaining
  -- deferred behavior for any later work in the caller's transaction.
  set constraints public.item_image_set_consistency, public.item_image_reference_consistency immediate;
  set constraints public.item_image_set_consistency, public.item_image_reference_consistency deferred;
 end if;
 result:=jsonb_build_object('attachmentId',u.id,'accountId',u.account_id,'principalId',u.principal_id,
  'itemId',u.item_id,'phase',case when rejection is null then 'applied' else 'rejected' end,
  'errorCode',rejection,'revision',new_revision::text,'position',target_position);
 insert into ledger_private.item_attachment_upload_results(upload_id,result) values(u.id,result);
 return result;
end;
$$;
revoke all on function ledger_private.publish_verified_item_attachment(uuid,text,text,bigint,text) from public,anon,authenticated,service_role;
create function public.spike_publish_verified_item_attachment(
 p_auth_user_id uuid,p_upload_id text,p_observed_sha256 text,p_observed_byte_count bigint,p_observed_media_type text
) returns jsonb language sql security definer set search_path='' as $$
 select ledger_private.publish_verified_item_attachment(p_auth_user_id,p_upload_id,p_observed_sha256,p_observed_byte_count,p_observed_media_type)
$$;
revoke all on function public.spike_publish_verified_item_attachment(uuid,text,text,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_publish_verified_item_attachment(uuid,text,text,bigint,text) to service_role;
