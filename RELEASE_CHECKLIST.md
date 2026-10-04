# PhotoSoap Release Checklist

Use this before submitting a build to App Store Connect.

## Required Before Submission

- Publish the `Docs` site and confirm the Privacy Policy URL returns HTTP 200: https://dermoha.github.io/PhotoSoap/privacy.html
- Confirm the Support URL returns HTTP 200 and its email link opens correctly: https://dermoha.github.io/PhotoSoap/support.html
- Enter the prepared answers from `APP_STORE_PRIVACY.md` and confirm they match `PRIVACY.md` and `PhotoSoap/PrivacyInfo.xcprivacy`.
- Confirm onboarding requires an explicit analytics choice, declining preserves all app functionality, and analytics can be disabled from Settings.
- Confirm `PhotoSoap/Configuration/Secrets.xcconfig` is ignored and not committed.
- Confirm Release builds include production `PHOTOSOAP_METRICS_ENDPOINT_URL` and `PHOTOSOAP_METRICS_ANON_KEY` values.
- Confirm the Supabase metrics ingest function is deployed and accepts production requests.
- Confirm the final merged Info.plist Photos permission copy matches the intended copy.
- Confirm device support is iPhone-only for v1, or reverse that decision and prepare iPad QA/screenshots.
- Confirm Stats shows overall totals plus separate photo and video counts and storage freed.
- Confirm existing users retain their totals after the media-stats migration and new video reviews update only the video bucket.

## Build Verification

```bash
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16e' build
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 16e'
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -configuration Release -destination 'generic/platform=iOS' build
```

## Real Device Smoke Test

- First launch onboarding
- Full Photos access
- Selected Photos access
- Permission denied and Settings recovery
- Photo preview
- Video preview
- Photos-only, videos-only, and all-media filters
- Favorites hidden by default in all, year, month, and album filters; turning the switch off restores them after relaunch
- Year/month percentages update after keeping media, queue rollback, new media, favorite visibility changes, and selected Photos access
- Swipe keep
- Swipe to Delete List
- Remove item from Delete List
- Clear Delete List
- Confirm batch deletion
- Cancel iOS deletion prompt and confirm stats/review state rolls back
- Confirm video keep, queued deletion, queue removal, batch deletion, and stats rollback paths
- Large library scrolling/review performance
- Analytics off: no pending metrics and no install ID
- Analytics on: install registration and aggregate metrics are queued/flushed

## App Store Metadata

- App name: PhotoSoap
- Category: Utilities
- Bundle ID: com.dermoha.PhotoSoap
- Version: 1.0
- Build: 12
- Privacy Policy URL: https://dermoha.github.io/PhotoSoap/privacy.html
- Support URL: https://dermoha.github.io/PhotoSoap/support.html
- Review notes explain that PhotoSoap uses Photos permission for local review and iOS shows the final deletion confirmation.
