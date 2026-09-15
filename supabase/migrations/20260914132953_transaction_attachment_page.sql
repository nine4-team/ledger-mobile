-- Reviewed local pull: omit environment/role-visibility artifacts, not product
-- functions or extensions. No table, writer, RLS or sync projection changes.
begin;

CREATE OR REPLACE FUNCTION public.spike_read_transaction_attachments(p_account_id text, p_transaction_id text, p_section text, p_start_position integer DEFAULT 0, p_limit integer DEFAULT 50, p_revision text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare parent record; marker record; entries jsonb; actual integer; first_position integer; last_position integer;
begin
 if (select auth.uid()) is null then raise exception using errcode='28000',message='authentication required'; end if;
 if not ledger_private.has_active_membership(p_account_id) then
  raise exception using errcode='42501',message='account_not_authorized';
 end if;
 if p_section is null or p_section not in ('receipts','other') or p_start_position is null or p_start_position<0
  or p_limit is null or p_limit<1 or p_limit>100 or (p_start_position>0 and p_revision is null) then
  raise exception using errcode='22023',message='transaction_attachment_page_invalid';
 end if;
 -- Canonical Transaction RLS, including current category, remains authority.
 select scope_kind,project_id,client_id into parent from public.spike_transactions
 where account_id=p_account_id and id=p_transaction_id;
 if not found then raise exception using errcode='42501',message='transaction_not_available'; end if;
 select revision,expected_count into marker from public.transaction_attachment_sets
 where account_id=p_account_id and transaction_id=p_transaction_id and section=p_section;
 if p_revision is not null and (marker.revision is null or marker.revision::text<>p_revision) then
  raise sqlstate 'PT409' using message='transaction_attachment_revision_changed';
 end if;
 if marker.revision is null then
  return jsonb_build_object('accountId',p_account_id,'principalId',ledger_private.current_principal_id(),
   'transactionId',p_transaction_id,'scopeKind',parent.scope_kind,'projectId',parent.project_id,'clientId',parent.client_id,
   'section',p_section,'revision',null,'expectedCount',null,'startPosition',0,'isComplete',false,'nextPosition',null,'attachments','[]'::jsonb);
 end if;
 if p_start_position>marker.expected_count then
  raise exception using errcode='22023',message='transaction_attachment_page_invalid';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'position',position,'isPrimary',is_primary,
   'kind',case when sync_media_type='application/pdf' then 'pdf' else 'image' end,'fileName',file_name) order by position),'[]'::jsonb),
   count(*)::integer,min(position),max(position) into entries,actual,first_position,last_position
 from (select id,position,is_primary,file_name,sync_media_type from public.transaction_attachment_references
   where account_id=p_account_id and transaction_id=p_transaction_id and section=p_section
    and set_revision=marker.revision and position>=p_start_position order by position,id limit p_limit) page;
 if actual<>least(p_limit,marker.expected_count-p_start_position)
  or (actual>0 and (first_position<>p_start_position or last_position<>p_start_position+actual-1)) then
  raise exception using errcode='22000',message='transaction_attachment_evidence_incomplete';
 end if;
 return jsonb_build_object('accountId',p_account_id,'principalId',ledger_private.current_principal_id(),
  'transactionId',p_transaction_id,'scopeKind',parent.scope_kind,'projectId',parent.project_id,'clientId',parent.client_id,
  'section',p_section,'revision',marker.revision::text,'expectedCount',marker.expected_count,'startPosition',p_start_position,
  'isComplete',p_start_position=0 and actual=marker.expected_count,
  'nextPosition',case when p_start_position+actual<marker.expected_count then p_start_position+actual else null end,
  'attachments',entries);
end;
$function$
;

revoke all on function public.spike_read_transaction_attachments(text,text,text,integer,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_transaction_attachments(text,text,text,integer,integer,text) to authenticated;
commit;
