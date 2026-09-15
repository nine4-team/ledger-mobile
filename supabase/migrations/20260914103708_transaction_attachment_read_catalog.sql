drop policy "item_image_objects_reference_read" on "public"."item_image_objects";

alter table "public"."item_image_objects" drop constraint "item_image_objects_media_type_check";


  create table "public"."transaction_attachment_references" (
    "id" text not null,
    "account_id" text not null,
    "transaction_id" text not null,
    "section" text not null,
    "attachment_id" text not null,
    "set_revision" bigint not null,
    "position" integer not null,
    "is_primary" boolean not null,
    "file_name" text
      );


alter table "public"."transaction_attachment_references" enable row level security;


  create table "public"."transaction_attachment_sets" (
    "id" text not null,
    "account_id" text not null,
    "transaction_id" text not null,
    "section" text not null,
    "revision" bigint not null,
    "expected_count" integer not null
      );


alter table "public"."transaction_attachment_sets" enable row level security;

CREATE UNIQUE INDEX transaction_attachment_one_primary ON public.transaction_attachment_references USING btree (account_id, transaction_id, section, set_revision) WHERE is_primary;

CREATE UNIQUE INDEX transaction_attachment_refere_account_id_transaction_id_se_key1 ON public.transaction_attachment_references USING btree (account_id, transaction_id, section, set_revision, attachment_id);

CREATE UNIQUE INDEX transaction_attachment_refere_account_id_transaction_id_sec_key ON public.transaction_attachment_references USING btree (account_id, transaction_id, section, set_revision, "position");

CREATE INDEX transaction_attachment_reference_object ON public.transaction_attachment_references USING btree (account_id, attachment_id);

CREATE UNIQUE INDEX transaction_attachment_references_pkey ON public.transaction_attachment_references USING btree (id);

CREATE UNIQUE INDEX transaction_attachment_sets_account_id_transaction_id_secti_key ON public.transaction_attachment_sets USING btree (account_id, transaction_id, section);

CREATE UNIQUE INDEX transaction_attachment_sets_pkey ON public.transaction_attachment_sets USING btree (id);

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_references_pkey" PRIMARY KEY using index "transaction_attachment_references_pkey";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_pkey" PRIMARY KEY using index "transaction_attachment_sets_pkey";

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_refere_account_id_transaction_id_se_fkey" FOREIGN KEY (account_id, transaction_id, section) REFERENCES public.transaction_attachment_sets(account_id, transaction_id, section) not valid;

alter table "public"."transaction_attachment_references" validate constraint "transaction_attachment_refere_account_id_transaction_id_se_fkey";

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_refere_account_id_transaction_id_se_key1" UNIQUE using index "transaction_attachment_refere_account_id_transaction_id_se_key1" DEFERRABLE INITIALLY DEFERRED;

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_refere_account_id_transaction_id_sec_key" UNIQUE using index "transaction_attachment_refere_account_id_transaction_id_sec_key" DEFERRABLE INITIALLY DEFERRED;

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_references_account_id_attachment_id_fkey" FOREIGN KEY (account_id, attachment_id) REFERENCES public.item_image_objects(account_id, id) not valid;

alter table "public"."transaction_attachment_references" validate constraint "transaction_attachment_references_account_id_attachment_id_fkey";

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_references_id_check" CHECK (((id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'::text) AND (octet_length(id) <= 128))) not valid;

alter table "public"."transaction_attachment_references" validate constraint "transaction_attachment_references_id_check";

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_references_position_check" CHECK (("position" >= 0)) not valid;

alter table "public"."transaction_attachment_references" validate constraint "transaction_attachment_references_position_check";

alter table "public"."transaction_attachment_references" add constraint "transaction_attachment_references_set_revision_check" CHECK ((set_revision > 0)) not valid;

alter table "public"."transaction_attachment_references" validate constraint "transaction_attachment_references_set_revision_check";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_account_id_transaction_id_fkey" FOREIGN KEY (account_id, transaction_id) REFERENCES public.spike_transactions(account_id, id) not valid;

alter table "public"."transaction_attachment_sets" validate constraint "transaction_attachment_sets_account_id_transaction_id_fkey";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_account_id_transaction_id_secti_key" UNIQUE using index "transaction_attachment_sets_account_id_transaction_id_secti_key";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_expected_count_check" CHECK ((expected_count >= 0)) not valid;

alter table "public"."transaction_attachment_sets" validate constraint "transaction_attachment_sets_expected_count_check";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_id_check" CHECK (((id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'::text) AND (octet_length(id) <= 128))) not valid;

alter table "public"."transaction_attachment_sets" validate constraint "transaction_attachment_sets_id_check";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_revision_check" CHECK ((revision > 0)) not valid;

alter table "public"."transaction_attachment_sets" validate constraint "transaction_attachment_sets_revision_check";

alter table "public"."transaction_attachment_sets" add constraint "transaction_attachment_sets_section_check" CHECK ((section = ANY (ARRAY['receipts'::text, 'other'::text]))) not valid;

alter table "public"."transaction_attachment_sets" validate constraint "transaction_attachment_sets_section_check";

alter table "public"."item_image_objects" add constraint "item_image_objects_media_type_check" CHECK (((media_type ~ '^image/[a-z0-9][a-z0-9.+-]{0,126}$'::text) OR (media_type = 'application/pdf'::text))) not valid;

alter table "public"."item_image_objects" validate constraint "item_image_objects_media_type_check";

grant select on table "public"."transaction_attachment_references" to "authenticated";

grant delete on table "public"."transaction_attachment_references" to "postgres";

grant insert on table "public"."transaction_attachment_references" to "postgres";

grant references on table "public"."transaction_attachment_references" to "postgres";

grant select on table "public"."transaction_attachment_references" to "postgres";

grant trigger on table "public"."transaction_attachment_references" to "postgres";

grant truncate on table "public"."transaction_attachment_references" to "postgres";

grant update on table "public"."transaction_attachment_references" to "postgres";

grant select on table "public"."transaction_attachment_sets" to "authenticated";

grant delete on table "public"."transaction_attachment_sets" to "postgres";

grant insert on table "public"."transaction_attachment_sets" to "postgres";

grant references on table "public"."transaction_attachment_sets" to "postgres";

grant select on table "public"."transaction_attachment_sets" to "postgres";

grant trigger on table "public"."transaction_attachment_sets" to "postgres";

grant truncate on table "public"."transaction_attachment_sets" to "postgres";

grant update on table "public"."transaction_attachment_sets" to "postgres";


  create policy "transaction_attachment_references_read"
  on "public"."transaction_attachment_references"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.transaction_attachment_sets s
  WHERE ((s.account_id = transaction_attachment_references.account_id) AND (s.transaction_id = transaction_attachment_references.transaction_id) AND (s.section = transaction_attachment_references.section) AND (s.revision = transaction_attachment_references.set_revision)))));



  create policy "transaction_attachment_sets_read"
  on "public"."transaction_attachment_sets"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.spike_transactions t
  WHERE ((t.account_id = transaction_attachment_sets.account_id) AND (t.id = transaction_attachment_sets.transaction_id)))));



  create policy "item_image_objects_reference_read"
  on "public"."item_image_objects"
  as permissive
  for select
  to authenticated
using ((( SELECT ledger_private.has_active_membership(item_image_objects.account_id) AS has_active_membership) AND ((EXISTS ( SELECT 1
   FROM public.item_image_references r
  WHERE ((r.account_id = item_image_objects.account_id) AND (r.attachment_id = item_image_objects.id)))) OR (EXISTS ( SELECT 1
   FROM public.item_card_thumbnails t
  WHERE ((t.account_id = item_image_objects.account_id) AND (t.thumbnail_attachment_id = item_image_objects.id)))) OR (EXISTS ( SELECT 1
   FROM public.transaction_attachment_references r
  WHERE ((r.account_id = item_image_objects.account_id) AND (r.attachment_id = item_image_objects.id)))))));


-- migra does not preserve FORCE RLS or these private trigger functions/grants.
-- Match the locally tested schema without introducing API write authority.
alter table public.transaction_attachment_sets force row level security;
alter table public.transaction_attachment_references force row level security;
revoke all on public.transaction_attachment_sets,public.transaction_attachment_references
  from public,anon,authenticated,service_role;
grant select on public.transaction_attachment_sets,public.transaction_attachment_references to authenticated;

create function ledger_private.check_item_image_media_type() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if exists(select 1 from public.item_image_objects o where o.account_id=new.account_id
   and o.id=new.attachment_id and o.media_type='application/pdf') then
   raise exception using errcode='23514',message='Item image references require image media';
 end if;
 return new;
end;
$$;

create function ledger_private.guard_transaction_attachment_parent() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if row(new.id,new.account_id,new.transaction_id,new.section) is distinct from row(old.id,old.account_id,old.transaction_id,old.section) then
   raise exception using errcode='55000',message='Transaction attachment parent identity is immutable';
 end if;
 return new;
end;
$$;

create function ledger_private.check_transaction_attachment_set() returns trigger
language plpgsql security invoker set search_path='' as $$
declare marker public.transaction_attachment_sets; actual_count bigint; primary_count bigint; first_position integer; last_position integer;
begin
 select * into marker from public.transaction_attachment_sets
 where account_id=coalesce(new.account_id,old.account_id) and transaction_id=coalesce(new.transaction_id,old.transaction_id)
 and section=coalesce(new.section,old.section) for update;
 if not found then return null; end if;
 select count(*),count(*) filter(where is_primary),min(position),max(position)
 into actual_count,primary_count,first_position,last_position from public.transaction_attachment_references
 where account_id=marker.account_id and transaction_id=marker.transaction_id and section=marker.section and set_revision=marker.revision;
 if actual_count<>marker.expected_count or primary_count>1 or (actual_count>0 and (first_position<>0 or last_position<>actual_count-1)) then
   raise exception using errcode='23514',message='Current Transaction attachment set is inconsistent';
 end if;
 return null;
end;
$$;
revoke all on function ledger_private.check_item_image_media_type(),
 ledger_private.guard_transaction_attachment_parent(),ledger_private.check_transaction_attachment_set()
 from public,anon,authenticated,service_role;

CREATE TRIGGER item_image_reference_media_type BEFORE INSERT OR UPDATE ON public.item_image_references FOR EACH ROW EXECUTE FUNCTION ledger_private.check_item_image_media_type();

CREATE CONSTRAINT TRIGGER transaction_attachment_reference_consistency AFTER INSERT OR DELETE OR UPDATE ON public.transaction_attachment_references DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_private.check_transaction_attachment_set();

CREATE TRIGGER transaction_attachment_references_parent BEFORE UPDATE ON public.transaction_attachment_references FOR EACH ROW EXECUTE FUNCTION ledger_private.guard_transaction_attachment_parent();

CREATE CONSTRAINT TRIGGER transaction_attachment_set_consistency AFTER INSERT OR UPDATE ON public.transaction_attachment_sets DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_private.check_transaction_attachment_set();

CREATE TRIGGER transaction_attachment_sets_parent BEFORE UPDATE ON public.transaction_attachment_sets FOR EACH ROW EXECUTE FUNCTION ledger_private.guard_transaction_attachment_parent();
