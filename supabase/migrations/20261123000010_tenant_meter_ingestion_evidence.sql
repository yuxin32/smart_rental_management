-- Evidence retained for simulated ingestion and backend-validation tests.

alter table public.electricity_reading
  add column if not exists ingestion_source varchar(30)
    not null default 'legacy_or_seed',
  add column if not exists ingestion_run_id varchar(80),
  add column if not exists raw_payload jsonb not null default '{}'::jsonb;

alter table public.electricity_reading
  drop constraint if exists electricity_reading_ingestion_source_check;

alter table public.electricity_reading
  add constraint electricity_reading_ingestion_source_check
    check (ingestion_source in (
      'legacy_or_seed',
      'admin_dataset_test',
      'esp32_physical'
    ));

create index if not exists ix_electricity_reading_ingestion_run
  on public.electricity_reading (ingestion_run_id)
  where ingestion_run_id is not null;
