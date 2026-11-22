-- Allow authenticated clients to receive new electricity readings through
-- Supabase Realtime. Existing row-level-security policies still determine
-- which records each administrator or tenant may read.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'electricity_reading'
  ) then
    alter publication supabase_realtime
      add table public.electricity_reading;
  end if;
end
$$;
