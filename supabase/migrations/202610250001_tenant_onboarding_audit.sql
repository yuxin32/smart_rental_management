-- Tenant onboarding audit trail and safe pending-invitation resend support.
-- The existing audit_log table is reused so administrators can trace the
-- tenant information, unit assignment, and invitation lifecycle.

create index if not exists idx_audit_log_entity_event
  on public.audit_log (entity_type, entity_id, event_timestamp desc);

create index if not exists idx_audit_log_action_event
  on public.audit_log (action_type, event_timestamp desc);

create or replace function public.audit_tenant_registration_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assigned_unit_number varchar(50);
begin
  -- The authenticated administrator is the actor for changes made through the
  -- application. Service-role changes do not have an auth.uid() and are
  -- logged explicitly by the invitation Edge Function instead.
  if (select auth.uid()) is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    insert into public.audit_log (
      actor_user_id,
      action_type,
      entity_type,
      entity_id,
      outcome,
      metadata
    ) values (
      (select auth.uid()),
      'TENANT_INFORMATION_ADDED',
      'tenant_registration',
      new.registration_id,
      'success',
      jsonb_build_object(
        'verification_status', new.verification_status,
        'registration_status', new.registration_status
      )
    );
  elsif tg_op = 'UPDATE'
    and new.unit_id is not null
    and (
      old.unit_id is distinct from new.unit_id
      or old.start_date is distinct from new.start_date
      or old.end_date is distinct from new.end_date
      or old.monthly_rental_amount is distinct from new.monthly_rental_amount
      or old.occupancy_share is distinct from new.occupancy_share
    ) then
    select unit_number
    into assigned_unit_number
    from public.rental_unit
    where unit_id = new.unit_id;

    insert into public.audit_log (
      actor_user_id,
      action_type,
      entity_type,
      entity_id,
      outcome,
      metadata
    ) values (
      (select auth.uid()),
      'TENANT_UNIT_ASSIGNED',
      'tenant_registration',
      new.registration_id,
      'success',
      jsonb_build_object(
        'unit_id', new.unit_id,
        'unit_number', assigned_unit_number,
        'start_date', new.start_date,
        'end_date', new.end_date,
        'monthly_rental_amount', new.monthly_rental_amount,
        'occupancy_share', new.occupancy_share
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_audit_tenant_registration_changes
  on public.tenant_registration;

create trigger trg_audit_tenant_registration_changes
after insert or update on public.tenant_registration
for each row execute function public.audit_tenant_registration_changes();

revoke all on function public.audit_tenant_registration_changes()
from public, anon, authenticated;
