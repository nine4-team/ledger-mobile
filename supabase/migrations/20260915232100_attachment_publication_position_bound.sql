-- Preserve the deployed publisher and its grants; bound the UInt32 reservation
-- position before narrowing to the gallery's integer position.
do $$
declare
  definition text := pg_get_functiondef(
    'public.spike_publish_verified_transaction_attachment(uuid,text,text,bigint,text)'::regprocedure);
  old_expression text := 'least(upload.local_position::integer,marker.expected_count)';
  new_expression text := 'least(upload.local_position,marker.expected_count::bigint)::integer';
begin
  if strpos(definition, new_expression) > 0 then return; end if;
  if strpos(definition, old_expression) = 0 then
    raise exception 'Expected attachment publisher position expression not found';
  end if;
  execute replace(definition, old_expression, new_expression);
end;
$$;
