import 'jsr:@supabase/functions-js/edge-runtime.d.ts'

import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabaseAdmin.ts'

const MAX_BUCKETS_PER_REQUEST = 14
const MAX_INSTALL_ID_LENGTH = 128
const MAX_TEXT_FIELD_LENGTH = 64

type RawPayload = {
  install_id?: unknown
  app_version?: unknown
  build_number?: unknown
  platform?: unknown
  submitted_at?: unknown
  register_install?: unknown
  daily_buckets?: unknown
}

type NormalizedBucket = {
  metric_date: string
  reviewed_photos: number
  deleted_photos: number
  kept_photos: number
  bytes_freed: number
  updated_at: string
}

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function asTrimmedString(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') {
    return null
  }

  const trimmed = value.trim()
  if (!trimmed || trimmed.length > maxLength) {
    return null
  }

  return trimmed
}

function asOptionalTrimmedString(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') {
    return null
  }

  const trimmed = value.trim()
  if (!trimmed) {
    return null
  }

  return trimmed.slice(0, maxLength)
}

function asNonNegativeInteger(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return 0
  }

  return Math.max(0, Math.floor(value))
}

function asIsoDateTime(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return null
  }

  return date.toISOString()
}

function normalizeBucket(rawBucket: unknown): NormalizedBucket | null {
  if (!rawBucket || typeof rawBucket !== 'object') {
    return null
  }

  const bucket = rawBucket as Record<string, unknown>
  const metricDate = asTrimmedString(bucket.metric_date, 10)
  if (!metricDate || !/^\d{4}-\d{2}-\d{2}$/.test(metricDate)) {
    return null
  }

  const deletedPhotos = asNonNegativeInteger(bucket.deleted_photos)
  const keptPhotos = asNonNegativeInteger(bucket.kept_photos)
  const reviewedPhotos = Math.max(asNonNegativeInteger(bucket.reviewed_photos), deletedPhotos + keptPhotos)
  const bytesFreed = asNonNegativeInteger(bucket.bytes_freed)
  const updatedAt = asIsoDateTime(bucket.updated_at) ?? new Date().toISOString()

  return {
    metric_date: metricDate,
    reviewed_photos: reviewedPhotos,
    deleted_photos: deletedPhotos,
    kept_photos: keptPhotos,
    bytes_freed: bytesFreed,
    updated_at: updatedAt,
  }
}

function mergeBucketsByDate(rawBuckets: unknown): NormalizedBucket[] {
  if (!Array.isArray(rawBuckets)) {
    return []
  }

  const mergedBuckets = new Map<string, NormalizedBucket>()

  for (const rawBucket of rawBuckets.slice(0, MAX_BUCKETS_PER_REQUEST)) {
    const bucket = normalizeBucket(rawBucket)
    if (!bucket) {
      continue
    }

    const existingBucket = mergedBuckets.get(bucket.metric_date)
    if (!existingBucket) {
      mergedBuckets.set(bucket.metric_date, bucket)
      continue
    }

    mergedBuckets.set(bucket.metric_date, {
      metric_date: bucket.metric_date,
      reviewed_photos: Math.max(existingBucket.reviewed_photos, bucket.reviewed_photos),
      deleted_photos: Math.max(existingBucket.deleted_photos, bucket.deleted_photos),
      kept_photos: Math.max(existingBucket.kept_photos, bucket.kept_photos),
      bytes_freed: Math.max(existingBucket.bytes_freed, bucket.bytes_freed),
      updated_at: existingBucket.updated_at > bucket.updated_at ? existingBucket.updated_at : bucket.updated_at,
    })
  }

  return [...mergedBuckets.values()].sort((left, right) => left.metric_date.localeCompare(right.metric_date))
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (request.method !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' })
  }

  let rawPayload: RawPayload
  try {
    rawPayload = await request.json()
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON payload' })
  }

  const installId = asTrimmedString(rawPayload.install_id, MAX_INSTALL_ID_LENGTH)
  if (!installId) {
    return jsonResponse(400, { error: 'install_id is required' })
  }

  const platform = asOptionalTrimmedString(rawPayload.platform, MAX_TEXT_FIELD_LENGTH) ?? 'ios'
  const appVersion = asOptionalTrimmedString(rawPayload.app_version, MAX_TEXT_FIELD_LENGTH)
  const buildNumber = asOptionalTrimmedString(rawPayload.build_number, MAX_TEXT_FIELD_LENGTH)
  const submittedAt = asIsoDateTime(rawPayload.submitted_at) ?? new Date().toISOString()
  const registerInstall = rawPayload.register_install === true
  const dailyBuckets = mergeBucketsByDate(rawPayload.daily_buckets)

  if (!registerInstall && dailyBuckets.length == 0) {
    return jsonResponse(200, { ok: true, ingested_bucket_count: 0, registered_install: false })
  }

  const { data, error } = await supabaseAdmin.rpc('ingest_aggregate_metrics', {
    p_install_id: installId,
    p_platform: platform,
    p_app_version: appVersion,
    p_build_number: buildNumber,
    p_client_submitted_at: submittedAt,
    p_register_install: registerInstall,
    p_daily_buckets: dailyBuckets,
  })

  if (error) {
    console.error('metrics-ingest failed', error)
    return jsonResponse(500, { error: 'Failed to ingest aggregate metrics' })
  }

  return jsonResponse(200, {
    ok: true,
    ingested_bucket_count: dailyBuckets.length,
    registered_install: registerInstall,
    result: data,
  })
})
