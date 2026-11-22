-- Administrator-only, preview/confirm cleanup of an EXACT registered test run.
-- Does not delete Auth identities, Storage objects, or any worked-on booking.
create function public.preview_test_fixture_cleanup(p_project_ref text,p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run public.test_data_run%rowtype;v_inventory jsonb;v_reasons text[]:='{}';v_digest jsonb;
begin
 perform public.require_test_environment(p_project_ref);
 select * into v_run from public.test_data_run where run_id=p_run_id;
 if not found then raise exception 'Unknown test run' using errcode='22023';end if;
 v_inventory:=public.inspect_test_run(p_project_ref,p_run_id);
 if not exists(select 1 from auth.users where id=v_run.owner_id and email='owner.'||p_run_id::text||'@rental-test.invalid') or
  not exists(select 1 from auth.users where id=v_run.provider_id and email='provider.'||p_run_id::text||'@rental-test.invalid') or
  not exists(select 1 from public.user_account where user_id=v_run.owner_id and role='owner' and email='owner.'||p_run_id::text||'@rental-test.invalid') or
  not exists(select 1 from public.user_account where user_id=v_run.provider_id and role='provider' and email='provider.'||p_run_id::text||'@rental-test.invalid') then
  v_reasons:=array_append(v_reasons,'Test identity changed');end if;
 if (v_inventory->>'mixed_account_bookings')::bigint<>0 then v_reasons:=array_append(v_reasons,'Mixed-account bookings');end if;
 if exists(select 1 from public.booking where (owner_id=v_run.owner_id or provider_id=v_run.provider_id) and
  current_status not in ('Pending','Declined','Cancelled')) or
  exists(select 1 from public.booking_status_history h join public.booking b using(booking_id)
   where (b.owner_id=v_run.owner_id or b.provider_id=v_run.provider_id) and h.new_status in ('Accepted','In Progress','Completed')) then
  v_reasons:=array_append(v_reasons,'Accepted or worked-on booking history');end if;
 if (v_inventory->'counts'->>'messages')::bigint>0 or (v_inventory->'counts'->>'reviews')::bigint>0 or
  (v_inventory->'counts'->>'evidence')::bigint>0 or (v_inventory->'counts'->>'upload_tickets')::bigint>0 or
  (v_inventory->'counts'->>'storage_metadata_objects')::bigint>0 then
  v_reasons:=array_append(v_reasons,'Chat, reviews, evidence or files require manual review');end if;
 if (v_inventory->'counts'->>'bookings')::bigint>100 or (v_inventory->'counts'->>'properties')::bigint>100 or
  (v_inventory->'counts'->>'status_history')::bigint>500 then
  v_reasons:=array_append(v_reasons,'Run exceeds small fixture cleanup limits');end if;
 -- Bounded eligible runs only. Never return private row content to the caller.
 if cardinality(v_reasons)=0 then
  select jsonb_build_object('run',to_jsonb(v_run),
   'accounts',(select jsonb_agg(to_jsonb(a) order by user_id) from public.user_account a where user_id in (v_run.owner_id,v_run.provider_id)),
   'profile',(select to_jsonb(p) from public.provider_profile p where provider_id=v_run.provider_id),
   'properties',(select jsonb_agg(to_jsonb(p) order by property_id) from public.property p where owner_id=v_run.owner_id),
   'slots',(select jsonb_agg(to_jsonb(s) order by slot_id) from public.provider_weekly_slot s where provider_id=v_run.provider_id),
   'dates',(select jsonb_agg(to_jsonb(d) order by unavailable_on) from public.provider_unavailable_date d where provider_id=v_run.provider_id),
   'capabilities',(select jsonb_agg(to_jsonb(c) order by service_type_id) from public.provider_capability c where provider_id=v_run.provider_id),
   'bookings',(select jsonb_agg(to_jsonb(b) order by booking_id) from public.booking b where owner_id=v_run.owner_id or provider_id=v_run.provider_id),
   'history',(select jsonb_agg(to_jsonb(h) order by status_history_id) from public.booking_status_history h join public.booking b using(booking_id)
    where b.owner_id=v_run.owner_id or b.provider_id=v_run.provider_id)) into v_digest;
 end if;
 return jsonb_build_object('run_id',p_run_id,'project_ref',p_project_ref,'counts',v_inventory->'counts',
  'eligible',cardinality(v_reasons)=0,'blockers',to_jsonb(v_reasons),
  'fingerprint',case when v_digest is not null then md5(v_digest::text) else null end,
  'auth_users_deleted',false,'storage_objects_deleted',false);
end;$$;
revoke all on function public.preview_test_fixture_cleanup(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.preview_test_fixture_cleanup(text,uuid) to service_role;

create function public.cleanup_test_fixture(p_project_ref text,p_run_id uuid,p_fingerprint text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run public.test_data_run%rowtype;v_plan jsonb;
begin
 perform public.require_test_environment(p_project_ref);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_run_id::text,16));
 select * into v_run from public.test_data_run where run_id=p_run_id for update;
 if not found then raise exception 'Unknown test run. Nothing deleted' using errcode='22023';end if;
 -- Prevent new FK-linked bookings/messages/uploads or reassigned identities
 -- between scope validation and removal. Re-check with fresh READ COMMITTED
 -- statements AFTER acquiring locks, not the earlier operator preview.
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'Cleanup requires read committed' using errcode='25000';end if;
 perform id from auth.users where id in (v_run.owner_id,v_run.provider_id) order by id for update;
 perform user_id from public.user_account where user_id in (v_run.owner_id,v_run.provider_id) order by user_id for update;
 perform provider_id from public.provider_profile where provider_id=v_run.provider_id for update;
 perform property_id from public.property where owner_id=v_run.owner_id order by property_id for update;
 perform booking_id from public.booking where owner_id=v_run.owner_id or provider_id=v_run.provider_id order by booking_id for update;
 v_plan:=public.preview_test_fixture_cleanup(p_project_ref,p_run_id);
 if not (v_plan->>'eligible')::boolean then raise exception 'Test run is not safe for automatic cleanup' using errcode='42501';end if;
 if p_fingerprint is null or p_fingerprint is distinct from v_plan->>'fingerprint' then
  raise exception 'Test run changed. Review a fresh cleanup preview' using errcode='40001';end if;
 -- Only pending/never-accepted, file-free, unmixed records reached this point.
 delete from public.booking where owner_id=v_run.owner_id and provider_id=v_run.provider_id;
 delete from public.property where owner_id=v_run.owner_id;
 delete from public.provider_unavailable_date where provider_id=v_run.provider_id;
 delete from public.provider_weekly_slot where provider_id=v_run.provider_id;
 delete from public.provider_capability where provider_id=v_run.provider_id;
 delete from public.provider_profile where provider_id=v_run.provider_id;
 delete from public.user_account where user_id in (v_run.owner_id,v_run.provider_id);
 delete from public.test_data_run where run_id=p_run_id;
 return v_plan||jsonb_build_object('cleaned',true,'auth_users_retained',2,'reseed_supported',true);
end;$$;
revoke all on function public.cleanup_test_fixture(text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.cleanup_test_fixture(text,uuid,text) to service_role;
