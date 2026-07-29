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

    if p_platform is null or p_platform not in ('ios', 'android') then
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
                bucket_deleted_photos := (bucket ->> 'deleted_photos')::bigint;
                bucket_kept_photos := (bucket ->> 'kept_photos')::bigint;
                bucket_reviewed_photos := (bucket ->> 'reviewed_photos')::bigint;
                bucket_bytes_freed := (bucket ->> 'bytes_freed')::bigint;
                bucket_updated_at := coalesce((bucket ->> 'updated_at')::timestamptz, effective_submitted_at);
            exception when others then
                raise exception 'Invalid daily bucket';
            end;

            if bucket_metric_date < current_date - 13
                or bucket_metric_date > current_date
                or bucket_reviewed_photos < 0 or bucket_reviewed_photos > 100000
                or bucket_deleted_photos < 0 or bucket_deleted_photos > 100000
                or bucket_kept_photos < 0 or bucket_kept_photos > 100000
                or bucket_deleted_photos + bucket_kept_photos > bucket_reviewed_photos
                or bucket_bytes_freed < 0 or bucket_bytes_freed > 10000000000000 then
                raise exception 'Invalid daily bucket';
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
