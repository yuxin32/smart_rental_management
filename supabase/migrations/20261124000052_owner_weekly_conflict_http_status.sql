-- Ported from 202610300034_weekly_conflict_http_status.sql; shared integrated names/roles are preserved.
-- Deterministic revision conflicts must not use a retryable serialization SQLSTATE.
-- PT409 returns HTTP 409 without PostgREST replay. Keep migration 033 immutable.
create or replace function public.replace_my_weekly_hours(p_changes jsonb,p_expected_revision text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 v_actor uuid:=auth.uid(); v_state jsonb; v_day jsonb; v_slot jsonb;
 v_days integer[]:='{}'; v_weekday integer; v_start integer; v_end integer;
 v_previous_end integer; v_job record;
begin
 if current_setting('transaction_isolation')<>'read committed' then
   raise exception 'Weekly updates require Read Committed' using errcode='25001';
 end if;
 perform 1 from public.provider_profile p join public.user_account a on a.user_id=p.provider_id
   where p.provider_id=v_actor and a.role='provider' for update of p;
 if not found then raise exception 'Provider session required' using errcode='42501';end if;
 if p_expected_revision is null or p_expected_revision!~'^[0-9a-f]{32}$' then
   raise exception 'Reload weekly hours before saving' using errcode='22023';
 end if;
 v_state:=app_private.provider_weekly_state(v_actor);
 if v_state->>'revision'<>p_expected_revision then
   raise exception 'Working hours changed; reload before saving' using errcode='PT409';
 end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' then
   raise exception 'Choose valid weekdays and time slots' using errcode='22023';
 end if;
 if jsonb_array_length(p_changes) not between 1 and 7 then
   raise exception 'Choose one to seven weekdays' using errcode='22023';
 end if;
 for v_day in select value from jsonb_array_elements(p_changes) loop
   if jsonb_typeof(v_day)<>'object' or not (v_day ?& array['weekday','slots']) or
      (v_day-array['weekday','slots'])<>'{}'::jsonb or
      jsonb_typeof(v_day->'weekday')<>'number' or (v_day->>'weekday')!~'^[1-7]$' or
      jsonb_typeof(v_day->'slots')<>'array' then
     raise exception 'Invalid weekday update' using errcode='22023';
   end if;
   v_weekday:=(v_day->>'weekday')::integer;
   if v_weekday=any(v_days) or jsonb_array_length(v_day->'slots')>12 then
     raise exception 'Duplicate weekday or too many time slots' using errcode='22023';
   end if;
   v_days:=array_append(v_days,v_weekday);
   for v_slot in select value from jsonb_array_elements(v_day->'slots') loop
     if jsonb_typeof(v_slot)<>'object' or not(v_slot ?& array['start_minute','end_minute']) or
        (v_slot-array['start_minute','end_minute'])<>'{}'::jsonb or
        jsonb_typeof(v_slot->'start_minute')<>'number' or jsonb_typeof(v_slot->'end_minute')<>'number' or
        (v_slot->>'start_minute')!~'^[0-9]{1,4}$' or (v_slot->>'end_minute')!~'^[0-9]{1,4}$' then
       raise exception 'Invalid working time' using errcode='22023';
     end if;
     v_start:=(v_slot->>'start_minute')::integer;v_end:=(v_slot->>'end_minute')::integer;
     if v_start<0 or v_end>1439 or v_end-v_start<120 then
       raise exception 'Each working slot must be at least 2 hours within one day' using errcode='23514';
     end if;
   end loop;
   v_previous_end:=-1;
   for v_slot in select value from jsonb_array_elements(v_day->'slots')
     order by (value->>'start_minute')::integer loop
     v_start:=(v_slot->>'start_minute')::integer;v_end:=(v_slot->>'end_minute')::integer;
     if v_start<v_previous_end then
       raise exception 'Working slots on the same day cannot overlap' using errcode='23514';
     end if;
     v_previous_end:=v_end;
   end loop;
   -- Wall-clock checks run after waiting for the same lock as acceptance.
   for v_job in select b.requested_start_at at time zone 'Asia/Kuala_Lumpur' as starts,
       b.requested_end_at at time zone 'Asia/Kuala_Lumpur' as ends
     from public.booking b where b.provider_id=v_actor
       and b.current_status in('Accepted','In Progress') and b.requested_end_at>clock_timestamp()
       and extract(isodow from b.requested_start_at at time zone 'Asia/Kuala_Lumpur')::integer=v_weekday
   loop
     if not exists(select 1 from jsonb_array_elements(v_day->'slots') s where
       make_time((s->>'start_minute')::integer/60,(s->>'start_minute')::integer%60,0)<=v_job.starts::time and
       make_time((s->>'end_minute')::integer/60,(s->>'end_minute')::integer%60,0)>=v_job.ends::time) then
       raise exception 'Availability change conflicts with a confirmed booking' using errcode='23514';
     end if;
   end loop;
 end loop;
 -- Only this constraint's timing changes, not its enforcement. Raw client
 -- operations remain immediately checked. Any exception rolls back all days.
 set constraints public.check_confirmed_weekly_slot_after deferred;
 delete from public.provider_weekly_slot where provider_id=v_actor and weekday=any(v_days);
 insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
 select v_actor,(d->>'weekday')::integer,
   make_time((s->>'start_minute')::integer/60,(s->>'start_minute')::integer%60,0),
   make_time((s->>'end_minute')::integer/60,(s->>'end_minute')::integer%60,0)
 from jsonb_array_elements(p_changes) d cross join lateral jsonb_array_elements(d->'slots') s;
 set constraints public.check_confirmed_weekly_slot_after immediate;
 return app_private.provider_weekly_state(v_actor);
end;
$$;
