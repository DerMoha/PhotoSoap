create schema if not exists private;

create table if not exists private.metrics_ingest_rate_limits (
    install_id text not null,
    window_date date not null default current_date,
    request_count integer not null default 0 check (request_count >= 0),
    last_request_at timestamptz not null default timezone('utc', now()),
    primary key (install_id, window_date)
);

revoke all on schema private from public, anon, authenticated;
revoke all on table private.metrics_ingest_rate_limits from public, anon, authenticated;

create table if not exists public.aggregate_metrics_summary (
    singleton boolean primary key default true check (singleton),
    total_installs bigint not null default 0 check (total_installs >= 0),
    total_reviewed bigint not null default 0 check (total_reviewed >= 0),
    total_deleted bigint not null default 0 check (total_deleted >= 0),
    total_kept bigint not null default 0 check (total_kept >= 0),
    total_bytes_freed bigint not null default 0 check (total_bytes_freed >= 0),
    updated_at timestamptz not null default timezone('utc', now())
);

alter table public.aggregate_metrics_summary enable row level security;

drop policy if exists "Allow public summary read" on public.aggregate_metrics_summary;
create policy "Allow public summary read"
on public.aggregate_metrics_summary
for select
to anon, authenticated
using (true);

revoke all on table public.aggregate_metrics_summary from public, anon, authenticated;
grant select on table public.aggregate_metrics_summary to anon, authenticated;
grant all on table public.aggregate_metrics_summary to service_role;

insert into public.aggregate_metrics_summary (
    singleton, total_installs, total_reviewed, total_deleted, total_kept, total_bytes_freed
)
select
    true,
    coalesce((select sum(installs) from public.daily_metrics), 0)::bigint
        + coalesce((select count(*) from public.app_install_registrations), 0)::bigint,
    coalesce((select sum(reviewed_photos) from public.daily_metrics), 0)::bigint
        + coalesce((select sum(reviewed_photos) from public.install_daily_metrics), 0)::bigint,
    coalesce((select sum(deleted_photos) from public.daily_metrics), 0)::bigint
        + coalesce((select sum(deleted_photos) from public.install_daily_metrics), 0)::bigint,
    coalesce((select sum(kept_photos) from public.daily_metrics), 0)::bigint
        + coalesce((select sum(kept_photos) from public.install_daily_metrics), 0)::bigint,
    coalesce((select sum(bytes_freed) from public.daily_metrics), 0)::bigint
        + coalesce((select sum(bytes_freed) from public.install_daily_metrics), 0)::bigint
on conflict (singleton) do update
set total_installs = excluded.total_installs,
    total_reviewed = excluded.total_reviewed,
    total_deleted = excluded.total_deleted,
    total_kept = excluded.total_kept,
    total_bytes_freed = excluded.total_bytes_freed,
    updated_at = timezone('utc', now());

drop view if exists public.aggregated_stats;

revoke all on table public.daily_metrics from anon, authenticated;
revoke all on table public.app_install_registrations from anon, authenticated;
revoke all on table public.install_daily_metrics from anon, authenticated;

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
set search_path = pg_catalog
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
    current_request_count integer;
begin
    if p_install_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        raise exception 'A valid install_id is required';
    end if;

    if p_platform is distinct from 'ios' then
        raise exception 'Unsupported platform';
    end if;

    if p_daily_buckets is not null
        and (jsonb_typeof(p_daily_buckets) <> 'array' or jsonb_array_length(p_daily_buckets) > 14) then
        raise exception 'Invalid daily_buckets';
    end if;

    insert into private.metrics_ingest_rate_limits (install_id, window_date, request_count, last_request_at)
    values (p_install_id, current_date, 1, timezone('utc', now()))
    on conflict (install_id, window_date) do update
    set request_count = private.metrics_ingest_rate_limits.request_count + 1,
        last_request_at = timezone('utc', now())
    returning request_count into current_request_count;

    if current_request_count > 12 then
        return jsonb_build_object('rate_limited', true);
    end if;

    delete from private.metrics_ingest_rate_limits
    where window_date < current_date - 30;

    if coalesce(p_register_install, false) then
        insert into public.app_install_registrations (install_id, first_seen, last_seen)
        values (p_install_id, effective_submitted_at, effective_submitted_at)
        on conflict (install_id) do update
        set first_seen = coalesce(public.app_install_registrations.first_seen, excluded.first_seen),
            last_seen = greatest(coalesce(public.app_install_registrations.last_seen, excluded.last_seen), excluded.last_seen);
    end if;

    if p_daily_buckets is not null and jsonb_typeof(p_daily_buckets) = 'array' then
        for bucket in select value from jsonb_array_elements(p_daily_buckets)
        loop
            begin
                bucket_metric_date := nullif(bucket ->> 'metric_date', '')::date;
                bucket_deleted_photos := coalesce((bucket ->> 'deleted_photos')::bigint, 0);
                bucket_kept_photos := coalesce((bucket ->> 'kept_photos')::bigint, 0);
                bucket_reviewed_photos := coalesce((bucket ->> 'reviewed_photos')::bigint, 0);
                bucket_bytes_freed := coalesce((bucket ->> 'bytes_freed')::bigint, 0);
                bucket_updated_at := coalesce((bucket ->> 'updated_at')::timestamptz, effective_submitted_at);
            exception when others then
                continue;
            end;

            if bucket_metric_date < current_date - 14
                or bucket_metric_date > current_date
                or bucket_reviewed_photos < 0 or bucket_reviewed_photos > 100000
                or bucket_deleted_photos < 0 or bucket_deleted_photos > 100000
                or bucket_kept_photos < 0 or bucket_kept_photos > 100000
                or bucket_deleted_photos + bucket_kept_photos > bucket_reviewed_photos
                or bucket_bytes_freed < 0 or bucket_bytes_freed > 10000000000000 then
                continue;
            end if;

            insert into public.install_daily_metrics (
                install_id, metric_date, reviewed_photos, deleted_photos, kept_photos,
                bytes_freed, platform, app_version, build_number, client_updated_at, received_at
            ) values (
                p_install_id, bucket_metric_date, bucket_reviewed_photos, bucket_deleted_photos,
                bucket_kept_photos, bucket_bytes_freed, p_platform,
                nullif(trim(p_app_version), ''), nullif(trim(p_build_number), ''),
                bucket_updated_at, timezone('utc', now())
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

    update public.aggregate_metrics_summary
    set total_installs = coalesce((select sum(installs) from public.daily_metrics), 0)::bigint
            + coalesce((select count(*) from public.app_install_registrations), 0)::bigint,
        total_reviewed = coalesce((select sum(reviewed_photos) from public.daily_metrics), 0)::bigint
            + coalesce((select sum(reviewed_photos) from public.install_daily_metrics), 0)::bigint,
        total_deleted = coalesce((select sum(deleted_photos) from public.daily_metrics), 0)::bigint
            + coalesce((select sum(deleted_photos) from public.install_daily_metrics), 0)::bigint,
        total_kept = coalesce((select sum(kept_photos) from public.daily_metrics), 0)::bigint
            + coalesce((select sum(kept_photos) from public.install_daily_metrics), 0)::bigint,
        total_bytes_freed = coalesce((select sum(bytes_freed) from public.daily_metrics), 0)::bigint
            + coalesce((select sum(bytes_freed) from public.install_daily_metrics), 0)::bigint,
        updated_at = timezone('utc', now())
    where singleton;

    return jsonb_build_object(
        'rate_limited', false,
        'ingested_bucket_count', ingested_bucket_count,
        'registered_install', coalesce(p_register_install, false)
    );
end;
$$;

revoke all on function public.ingest_aggregate_metrics(text, text, text, text, timestamptz, boolean, jsonb)
from public, anon, authenticated;
grant execute on function public.ingest_aggregate_metrics(text, text, text, text, timestamptz, boolean, jsonb)
to service_role;

revoke all on function public.rls_auto_enable() from public, anon, authenticated;
