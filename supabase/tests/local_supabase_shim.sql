-- Disposable PostgreSQL-only shim for syntax/RLS testing. This is not the
-- real Supabase Auth or Storage service and must never be applied remotely.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role supabase_admin nologin;
grant usage on schema public to anon, authenticated, service_role;
-- Exercise BOTH observed initial states; these are shim-only psql variables.
-- Broad hosted legacy defaults versus disabled Data API exposure defaults.
\if :broad_defaults
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
\else
alter default privileges in schema public
  grant truncate,references,trigger on tables to anon,authenticated,service_role;
alter default privileges in schema public
  grant update on sequences to anon,authenticated,service_role;
\endif
-- Platform role defaults do NOT flow into tables created as postgres.
alter default privileges for role supabase_admin in schema public
  grant all on tables to anon,authenticated,service_role;

create schema auth;
grant usage on schema auth to anon,authenticated,service_role;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  )
$$;

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  bucket_id text not null references storage.buckets(id),
  name text not null,
  metadata jsonb not null default '{}',
  primary key (bucket_id, name)
);
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select, insert on storage.objects to authenticated;
create function storage.extension(path text) returns text
language sql immutable as $$
  select split_part(path, '.', array_length(string_to_array(path, '.'), 1))
$$;
create function storage.foldername(path text) returns text[]
language sql immutable as $$
  select string_to_array(path, '/')
$$;

create publication supabase_realtime;
