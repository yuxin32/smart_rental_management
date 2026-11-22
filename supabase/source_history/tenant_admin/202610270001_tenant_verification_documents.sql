-- Tenant-submitted verification documents.
-- The document binary is kept in a private Storage bucket. The database
-- stores only the storage paths, submission metadata, and administrator review.

create or replace function public.is_allowed_verification_file(file_path text)
returns boolean
language sql
immutable
as $$
  select lower(file_path) like '%.pdf'
      or lower(file_path) like '%.jpg'
      or lower(file_path) like '%.jpeg'
      or lower(file_path) like '%.png'
      or lower(file_path) like '%.webp'
      or lower(file_path) like '%.heic'
      or lower(file_path) like '%.heif';
$$;

revoke all on function public.is_allowed_verification_file(text)
from public, anon, authenticated;
grant execute on function public.is_allowed_verification_file(text)
to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'tenant-verification-documents',
  'tenant-verification-documents',
  false,
  10485760,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array[
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    ]::text[];

alter table public.tenant_registration
  add column if not exists documents_submitted_at timestamptz,
  add column if not exists verification_notes text,
  add column if not exists verification_reviewed_by_admin_id uuid
    references public.admin(admin_id),
  add column if not exists verification_reviewed_at timestamptz;

-- Before this workflow, invited and accepted registrations were required to
-- have an assigned unit. A tenant must now be able to accept an invitation
-- and submit documents before a unit is assigned.
alter table public.tenant_registration
  drop constraint if exists complete_assignment;

alter table public.tenant_registration
  drop constraint if exists valid_assignment_status;

alter table public.tenant_registration
  add constraint valid_assignment_status check (
    registration_status <> 'assigned'
    or (
      unit_id is not null
      and start_date is not null
      and monthly_rental_amount is not null
      and monthly_rental_amount >= 0
    )
  );

drop policy if exists tenant_registration_tenant_select
  on public.tenant_registration;
create policy tenant_registration_tenant_select
on public.tenant_registration for select to authenticated
using (auth_user_id = (select auth.uid()));

drop policy if exists tenant_verification_documents_select
  on storage.objects;
create policy tenant_verification_documents_select
on storage.objects for select to authenticated
using (
  bucket_id = 'tenant-verification-documents'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
  )
);

drop policy if exists tenant_verification_documents_insert
  on storage.objects;
create policy tenant_verification_documents_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'tenant-verification-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.is_allowed_verification_file(name)
);

drop policy if exists tenant_verification_documents_update
  on storage.objects;
create policy tenant_verification_documents_update
on storage.objects for update to authenticated
using (
  bucket_id = 'tenant-verification-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'tenant-verification-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.is_allowed_verification_file(name)
);

drop policy if exists tenant_verification_documents_delete
  on storage.objects;
create policy tenant_verification_documents_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'tenant-verification-documents'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
  )
);

create or replace function public.complete_current_tenant_setup()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    return false;
  end if;

  update public.user_account
  set invitation_status = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where user_id = current_user_id
    and role = 'tenant'
    and account_status = 'pending'
    and invitation_status = 'invited';

  if not found and not exists (
    select 1
    from public.user_account
    where user_id = current_user_id
      and role = 'tenant'
      and invitation_status = 'accepted'
  ) then
    return false;
  end if;

  update public.tenant_registration
  set registration_status = case
        when registration_status = 'invited' then 'accepted'
        else registration_status
      end,
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where auth_user_id = current_user_id;

  return true;
end;
$$;

grant execute on function public.complete_current_tenant_setup() to authenticated;

create or replace function public.submit_tenant_verification_documents(
  p_identity_document_path text,
  p_employment_or_study_proof_path text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    return false;
  end if;

  if p_identity_document_path is null
     or p_employment_or_study_proof_path is null
     or not public.is_allowed_verification_file(p_identity_document_path)
     or not public.is_allowed_verification_file(p_employment_or_study_proof_path)
     or split_part(p_identity_document_path, '/', 1) <> current_user_id::text
     or split_part(p_employment_or_study_proof_path, '/', 1) <> current_user_id::text then
    raise exception 'Invalid verification document path.';
  end if;

  update public.tenant_registration
  set identity_document_path = p_identity_document_path,
      employment_or_study_proof_path = p_employment_or_study_proof_path,
      documents_submitted_at = now(),
      verification_status = 'pending',
      verification_notes = null,
      verification_reviewed_by_admin_id = null,
      verification_reviewed_at = null,
      updated_at = now()
  where auth_user_id = current_user_id
    and registration_status in ('invited', 'accepted');

  if not found then
    return false;
  end if;

  update public.tenant
  set identity_document_path = p_identity_document_path,
      employment_or_study_proof_path = p_employment_or_study_proof_path,
      verification_status = 'pending',
      is_verified = false,
      verified_by_admin_id = null,
      verified_at = null
  where tenant_id = current_user_id;

  return true;
end;
$$;

grant execute on function public.submit_tenant_verification_documents(text, text)
to authenticated;

create or replace function public.review_tenant_verification(
  p_registration_id uuid,
  p_verification_status varchar,
  p_verification_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  target_user_id uuid;
  identity_path text;
  proof_path text;
begin
  if current_admin_id is null or not public.is_admin() then
    return false;
  end if;

  if p_verification_status not in ('verified', 'rejected', 'pending') then
    raise exception 'Invalid verification status.';
  end if;

  select auth_user_id, identity_document_path, employment_or_study_proof_path
  into target_user_id, identity_path, proof_path
  from public.tenant_registration
  where registration_id = p_registration_id;

  if not found then
    raise exception 'Tenant registration was not found.';
  end if;

  if p_verification_status = 'verified'
     and (identity_path is null or proof_path is null) then
    raise exception 'Both tenant verification documents are required.';
  end if;

  update public.tenant_registration
  set verification_status = p_verification_status,
      verification_notes = nullif(trim(coalesce(p_verification_notes, '')), ''),
      verification_reviewed_by_admin_id = current_admin_id,
      verification_reviewed_at = now(),
      updated_at = now()
  where registration_id = p_registration_id;

  if target_user_id is not null then
    update public.tenant
    set verification_status = p_verification_status,
        is_verified = p_verification_status = 'verified',
        verified_by_admin_id = case
          when p_verification_status = 'verified' then current_admin_id
          else null
        end,
        verified_at = case
          when p_verification_status = 'verified' then now()
          else null
        end
    where tenant_id = target_user_id;
  end if;

  insert into public.audit_log (
    actor_user_id,
    action_type,
    entity_type,
    entity_id,
    outcome,
    metadata
  ) values (
    current_admin_id,
    'TENANT_VERIFICATION_REVIEWED',
    'tenant_registration',
    p_registration_id,
    'success',
    jsonb_build_object(
      'verification_status', p_verification_status,
      'has_identity_document', identity_path is not null,
      'has_employment_or_study_proof', proof_path is not null
    )
  );

  return true;
end;
$$;

grant execute on function public.review_tenant_verification(uuid, varchar, text)
to authenticated;

create or replace function public.assign_verified_tenant(
  p_registration_id uuid,
  p_unit_id uuid,
  p_start_date date,
  p_end_date date,
  p_monthly_rental_amount numeric,
  p_occupancy_share numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  target_user_id uuid;
  previous_unit_id uuid;
  existing_tenancy_id uuid;
begin
  if current_admin_id is null or not public.is_admin() then
    return false;
  end if;

  if p_start_date is null
     or p_monthly_rental_amount is null
     or p_monthly_rental_amount < 0
     or p_occupancy_share <= 0
     or p_occupancy_share > 1
     or (p_end_date is not null and p_end_date < p_start_date) then
    raise exception 'Invalid tenancy details.';
  end if;

  select auth_user_id
  into target_user_id
  from public.tenant_registration
  where registration_id = p_registration_id
    and verification_status = 'verified';

  if target_user_id is null then
    raise exception 'The tenant must be verified before unit assignment.';
  end if;

  select tenancy_id, unit_id
  into existing_tenancy_id, previous_unit_id
  from public.tenancy
  where tenant_id = target_user_id
    and tenancy_status in ('pending', 'active')
  order by start_date desc
  limit 1;

  if previous_unit_id is not null and previous_unit_id <> p_unit_id then
    update public.rental_unit
    set unit_status = 'available'
    where unit_id = previous_unit_id;
  end if;

  if existing_tenancy_id is null then
    insert into public.tenancy (
      tenant_id,
      unit_id,
      start_date,
      end_date,
      monthly_rental_amount,
      occupancy_share,
      tenancy_status
    ) values (
      target_user_id,
      p_unit_id,
      p_start_date,
      p_end_date,
      p_monthly_rental_amount,
      p_occupancy_share,
      'active'
    );
  else
    update public.tenancy
    set unit_id = p_unit_id,
        start_date = p_start_date,
        end_date = p_end_date,
        monthly_rental_amount = p_monthly_rental_amount,
        occupancy_share = p_occupancy_share,
        tenancy_status = 'active'
    where tenancy_id = existing_tenancy_id;
  end if;

  update public.rental_unit
  set unit_status = 'occupied'
  where unit_id = p_unit_id;

  update public.tenant_registration
  set unit_id = p_unit_id,
      start_date = p_start_date,
      end_date = p_end_date,
      monthly_rental_amount = p_monthly_rental_amount,
      occupancy_share = p_occupancy_share,
      registration_status = 'assigned',
      updated_at = now()
  where registration_id = p_registration_id;

  update public.user_account
  set account_status = 'active',
      updated_at = now()
  where user_id = target_user_id
    and invitation_status = 'accepted';

  return true;
end;
$$;

grant execute on function public.assign_verified_tenant(uuid, uuid, date, date, numeric, numeric)
to authenticated;
