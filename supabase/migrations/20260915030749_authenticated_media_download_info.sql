DROP POLICY "ledger_account_profile_logo_download" ON "storage"."objects";

DROP POLICY "ledger_item_image_download" ON "storage"."objects";

DROP POLICY "transaction_attachment_reserved_read" ON "storage"."objects";

CREATE POLICY "ledger_account_profile_logo_download" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'ledger-attachments'::text) AND storage.allow_any_operation(ARRAY['object.get_authenticated'::text, 'object.get_authenticated_info'::text]) AND (EXISTS ( SELECT
    1
   FROM public.spike_account_business_profiles profile
  WHERE ((profile.logo_storage_path = objects.name) AND ledger_private.has_active_membership(profile.account_id))))));

CREATE POLICY "ledger_item_image_download" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'ledger-attachments'::text) AND storage.allow_any_operation(ARRAY['object.get_authenticated'::text, 'object.get_authenticated_info'::text]) AND (EXISTS ( SELECT
    1
   FROM public.item_image_objects image
  WHERE ((image.storage_path = objects.name) AND ledger_private.has_active_membership(image.account_id))))));

CREATE POLICY "transaction_attachment_reserved_read" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'ledger-attachments'::text) AND storage.allow_any_operation(ARRAY['object.get_authenticated'::text, 'object.get_authenticated_info'::text]) AND (EXISTS ( SELECT
    1
   FROM public.transaction_attachment_uploads u
  WHERE (u.storage_path = objects.name)))));
