create table if not exists public.install_daily_metrics (
    install_id text not null,
    metric_date date not null,
    reviewed_photos bigint not null default 0 check (reviewed_photos >= 0),
    deleted_photos bigint not null default 0 check (deleted_photos >= 0),
    kept_photos bigint not null default 0 check (kept_photos >= 0),
    bytes_freed bigint not null default 0 check (bytes_freed >= 0),
    platform text not null default 'ios',
    app_version text,
    build_number text,
    client_updated_at timestamptz,
    received_at timestamptz not null default timezone('utc', now()),
    created_at timestamptz not null default timezone('utc', now()),
    constraint install_daily_metrics_pkey primary key (install_id, metric_date)
);

alter table public.install_daily_metrics enable row level security;

drop policy if exists "Allow anonymous inserts" on public.app_install_registrations;

drop policy if exists "Allow service read" on public.install_daily_metrics;
create policy "Allow service read"
on public.install_daily_metrics
for select
to service_role
using (true);

drop policy if exists "Allow service update" on public.install_daily_metrics;
create policy "Allow service update"
on public.install_daily_metrics
for update
to service_role
using (true)
with check (true);

drop policy if exists "Allow service write" on public.install_daily_metrics;
create policy "Allow service write"
on public.install_daily_metrics
for insert
to service_role
with check (true);

create or replace function public.ingest_aggregate_metrics(
    p_install_id text,
    p_platform text,
    p_app_version text,
    p_build_number text,
    p_client_submitted_at timestamptz,
    p_register_install boolean,
    p_daily_buckets jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    bucket jsonb;
    bucket_metric_date date;
    bucket_reviewed_photos bigint;
    bucket_deleted_photos bigint;
    bucket_kept_photos bigint;
    bucket_bytes_freed bigint;
    bucket_updated_at timestamptz;
    effective_submitted_at timestamptz := coalesce(p_client_submitted_at, timezone('utc', now()));
    ingested_bucket_count integer := 0;
begin
    if coalesce(trim(p_install_id), '') = '' then
        raise exception 'install_id is required';
    end if;

    if coalesce(p_register_install, false) then
        insert into public.app_install_registrations (
            install_id,
            first_seen,
            last_seen
        )
        values (
            p_install_id,
            effective_submitted_at,
            effective_submitted_at
        )
        on conflict (install_id) do update
        set first_seen = coalesce(public.app_install_registrations.first_seen, excluded.first_seen),
            last_seen = greatest(coalesce(public.app_install_registrations.last_seen, excluded.last_seen), excluded.last_seen);
    end if;

    if p_daily_buckets is not null and jsonb_typeof(p_daily_buckets) = 'array' then
        for bucket in
            select value
            from jsonb_array_elements(p_daily_buckets)
        loop
            begin
                bucket_metric_date := nullif(bucket ->> 'metric_date', '')::date;
                bucket_deleted_photos := greatest(coalesce((bucket ->> 'deleted_photos')::bigint, 0), 0);
                bucket_kept_photos := greatest(coalesce((bucket ->> 'kept_photos')::bigint, 0), 0);
                bucket_reviewed_photos := greatest(
                    coalesce((bucket ->> 'reviewed_photos')::bigint, 0),
                    bucket_deleted_photos + bucket_kept_photos
                );
                bucket_bytes_freed := greatest(coalesce((bucket ->> 'bytes_freed')::bigint, 0), 0);
                bucket_updated_at := coalesce((bucket ->> 'updated_at')::timestamptz, effective_submitted_at);
            exception
                when others then
                    continue;
            end;

            if bucket_metric_date is null then
                continue;
            end if;

            insert into public.install_daily_metrics (
                install_id,
                metric_date,
                reviewed_photos,
                deleted_photos,
                kept_photos,
                bytes_freed,
                platform,
                app_version,
                build_number,
                client_updated_at,
                received_at
            )
            values (
                p_install_id,
                bucket_metric_date,
                bucket_reviewed_photos,
                bucket_deleted_photos,
                bucket_kept_photos,
                bucket_bytes_freed,
                coalesce(nullif(trim(p_platform), ''), 'ios'),
                nullif(trim(p_app_version), ''),
                nullif(trim(p_build_number), ''),
                bucket_updated_at,
                timezone('utc', now())
            )
            on conflict (install_id, metric_date) do update
            set reviewed_photos = greatest(public.install_daily_metrics.reviewed_photos, excluded.reviewed_photos),
                deleted_photos = greatest(public.install_daily_metrics.deleted_photos, excluded.deleted_photos),
                kept_photos = greatest(public.install_daily_metrics.kept_photos, excluded.kept_photos),
                bytes_freed = greatest(public.install_daily_metrics.bytes_freed, excluded.bytes_freed),
                platform = excluded.platform,
                app_version = excluded.app_version,
                build_number = excluded.build_number,
                client_updated_at = greatest(coalesce(public.install_daily_metrics.client_updated_at, excluded.client_updated_at), excluded.client_updated_at),
                received_at = timezone('utc', now());

            ingested_bucket_count := ingested_bucket_count + 1;
        end loop;
    end if;

    return jsonb_build_object(
        'ingested_bucket_count', ingested_bucket_count,
        'registered_install', coalesce(p_register_install, false)
    );
end;
$$;

revoke all on function public.ingest_aggregate_metrics(text, text, text, text, timestamptz, boolean, jsonb) from public;
grant execute on function public.ingest_aggregate_metrics(text, text, text, text, timestamptz, boolean, jsonb) to service_role;

create or replace view public.aggregated_stats as
with legacy_metrics as (
    select
        coalesce(sum(installs), 0)::bigint as total_installs,
        coalesce(sum(reviewed_photos), 0)::bigint as total_reviewed,
        coalesce(sum(deleted_photos), 0)::bigint as total_deleted,
        coalesce(sum(kept_photos), 0)::bigint as total_kept,
        coalesce(sum(bytes_freed), 0)::bigint as total_bytes_freed
    from public.daily_metrics
),
current_metrics as (
    select
        coalesce(sum(reviewed_photos), 0)::numeric as total_reviewed,
        coalesce(sum(deleted_photos), 0)::numeric as total_deleted,
        coalesce(sum(kept_photos), 0)::numeric as total_kept,
        coalesce(sum(bytes_freed), 0)::numeric as total_bytes_freed
    from public.install_daily_metrics
),
install_registrations as (
    select
        count(*)::bigint as total_installs
    from public.app_install_registrations
)
select
    legacy_metrics.total_installs + install_registrations.total_installs as total_installs,
    legacy_metrics.total_reviewed + current_metrics.total_reviewed as total_reviewed,
    legacy_metrics.total_deleted + current_metrics.total_deleted as total_deleted,
    legacy_metrics.total_kept + current_metrics.total_kept as total_kept,
    legacy_metrics.total_bytes_freed + current_metrics.total_bytes_freed as total_bytes_freed
from legacy_metrics
cross join current_metrics
cross join install_registrations;
