-- Administrator-owned environment identity. Applying migrations must NOT
-- silently label an existing project as staging or production.
create table public.app_deployment_environment (
  singleton boolean primary key default true check (singleton),
  environment text not null default 'unassigned'
    check (environment in ('unassigned', 'staging', 'production')),
  project_ref text,
  configured_at timestamptz not null default now(),
  constraint deployment_environment_assignment check (
    (environment = 'unassigned' and project_ref is null) or
    (environment in ('staging', 'production') and project_ref ~ '^[a-z]{20}$'
      and project_ref is not null)
  )
);
insert into public.app_deployment_environment(singleton) values (true);
alter table public.app_deployment_environment enable row level security;
revoke all on public.app_deployment_environment from public, anon, authenticated;

-- No user data, keys or credentials are exposed. Login is deliberately not
-- needed: the app must check this before restoring any saved Auth session.
create function public.get_app_environment()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('environment', environment, 'project_ref', project_ref)
  from public.app_deployment_environment where singleton;
$$;
revoke all on function public.get_app_environment() from public;
grant execute on function public.get_app_environment() to anon, authenticated;
