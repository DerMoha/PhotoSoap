import 'jsr:@supabase/functions-js/edge-runtime.d.ts'

import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabaseAdmin.ts'

const MAX_BUCKETS_PER_REQUEST = 14
const MAX_INSTALL_ID_LENGTH = 128
const MAX_TEXT_FIELD_LENGTH = 64
const MAX_PHOTOS_PER_DAY = 100_000
const MAX_BYTES_FREED_PER_DAY = 10_000_000_000_000
const INSTALL_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const SUPPORTED_PLATFORMS = new Set(['ios', 'android'])

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

function asBoundedNonNegativeInteger(value: unknown, maximum: number): number | null {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > maximum) {
    return null
  }

  return value
}

function configuredPublishableKeys(): string[] {
  const configuredKeys = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')
  if (configuredKeys) {
    try {
      const parsed = JSON.parse(configuredKeys) as Record<string, unknown>
      return Object.values(parsed).filter((value): value is string => typeof value === 'string')
    } catch {
      console.error('Invalid SUPABASE_PUBLISHABLE_KEYS configuration')
    }
  }

  const legacyAnonKey = Deno.env.get('SUPABASE_ANON_KEY')
  return legacyAnonKey ? [legacyAnonKey] : []
}

function hasValidApiKey(request: Request): boolean {
  const apiKey = request.headers.get('apikey')
  return apiKey !== null && configuredPublishableKeys().includes(apiKey)
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

  const reviewedPhotos = asBoundedNonNegativeInteger(bucket.reviewed_photos, MAX_PHOTOS_PER_DAY)
  const deletedPhotos = asBoundedNonNegativeInteger(bucket.deleted_photos, MAX_PHOTOS_PER_DAY)
  const keptPhotos = asBoundedNonNegativeInteger(bucket.kept_photos, MAX_PHOTOS_PER_DAY)
  const bytesFreed = asBoundedNonNegativeInteger(bucket.bytes_freed, MAX_BYTES_FREED_PER_DAY)
  const updatedAt = asIsoDateTime(bucket.updated_at) ?? new Date().toISOString()

  if (
    reviewedPhotos === null ||
    deletedPhotos === null ||
    keptPhotos === null ||
    bytesFreed === null ||
    deletedPhotos + keptPhotos > reviewedPhotos
  ) {
    return null
  }

  const today = new Date()
  const earliestDate = new Date(today)
  earliestDate.setUTCDate(earliestDate.getUTCDate() - (MAX_BUCKETS_PER_REQUEST - 1))
  const parsedMetricDate = new Date(`${metricDate}T00:00:00.000Z`)
  if (
    Number.isNaN(parsedMetricDate.getTime()) ||
    parsedMetricDate.toISOString().slice(0, 10) !== metricDate ||
    parsedMetricDate > today ||
    parsedMetricDate < earliestDate
  ) {
    return null
  }

  return {
    metric_date: metricDate,
    reviewed_photos: reviewedPhotos,
    deleted_photos: deletedPhotos,
    kept_photos: keptPhotos,
    bytes_freed: bytesFreed,
    updated_at: updatedAt,
  }
}

function mergeBucketsByDate(rawBuckets: unknown): NormalizedBucket[] | null {
  if (!Array.isArray(rawBuckets) || rawBuckets.length > MAX_BUCKETS_PER_REQUEST) {
    return null
  }

  const mergedBuckets = new Map<string, NormalizedBucket>()

  for (const rawBucket of rawBuckets) {
    const bucket = normalizeBucket(rawBucket)
    if (!bucket) {
      return null
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

  if (!hasValidApiKey(request)) {
    return jsonResponse(401, { error: 'Invalid API key' })
  }

  let rawPayload: RawPayload
  try {
    rawPayload = await request.json()
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON payload' })
  }

  const installId = asTrimmedString(rawPayload.install_id, MAX_INSTALL_ID_LENGTH)
  if (!installId || !INSTALL_ID_PATTERN.test(installId)) {
    return jsonResponse(400, { error: 'A valid install_id is required' })
  }

  const platform = asOptionalTrimmedString(rawPayload.platform, MAX_TEXT_FIELD_LENGTH) ?? 'ios'
  if (!SUPPORTED_PLATFORMS.has(platform)) {
    return jsonResponse(400, { error: 'Unsupported platform' })
  }
  const appVersion = asOptionalTrimmedString(rawPayload.app_version, MAX_TEXT_FIELD_LENGTH)
  const buildNumber = asOptionalTrimmedString(rawPayload.build_number, MAX_TEXT_FIELD_LENGTH)
  const submittedAt = asIsoDateTime(rawPayload.submitted_at) ?? new Date().toISOString()
  const registerInstall = rawPayload.register_install === true
  const dailyBuckets = mergeBucketsByDate(rawPayload.daily_buckets ?? [])
  if (dailyBuckets === null) {
    return jsonResponse(400, { error: 'Invalid daily_buckets' })
  }

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

  if (data?.rate_limited === true) {
    return jsonResponse(429, { error: 'Rate limit exceeded' })
  }

  return jsonResponse(200, {
    ok: true,
    ingested_bucket_count: dailyBuckets.length,
    registered_install: registerInstall,
    result: data,
  })
})
