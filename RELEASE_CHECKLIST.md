# PhotoSoap Release Checklist

Use this before submitting a build to App Store Connect.

## Required Before Submission

- Confirm the Privacy Policy URL is public: https://github.com/DerMoha/PhotoSoap/blob/main/PRIVACY.md
- Confirm the Support URL is public: https://github.com/DerMoha/PhotoSoap/issues
- Confirm App Store privacy labels match `PRIVACY.md` and `PhotoSoap/PrivacyInfo.xcprivacy`.
- Confirm optional usage analytics are off by default and can be disabled from Settings.
- Confirm `PhotoSoap/Configuration/Secrets.xcconfig` is ignored and not committed.
- Confirm Release builds include production `PHOTOSOAP_METRICS_ENDPOINT_URL` and `PHOTOSOAP_METRICS_ANON_KEY` values.
- Confirm the Supabase metrics ingest function is deployed and accepts production requests.
- Confirm the final merged Info.plist Photos permission copy matches the intended copy.
- Confirm device support is iPhone-only for v1, or reverse that decision and prepare iPad QA/screenshots.

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
- Swipe keep
- Swipe to Delete List
- Remove item from Delete List
- Clear Delete List
- Confirm batch deletion
- Cancel iOS deletion prompt and confirm stats/review state rolls back
- Large library scrolling/review performance
- Analytics off: no pending metrics and no install ID
- Analytics on: install registration and aggregate metrics are queued/flushed

## App Store Metadata

- App name: PhotoSoap
- Category: Utilities
- Bundle ID: com.dermoha.PhotoSoap
- Version: 1.0
- Build: 1
- Privacy Policy URL: https://github.com/DerMoha/PhotoSoap/blob/main/PRIVACY.md
- Support URL: https://github.com/DerMoha/PhotoSoap/issues
- Review notes explain that PhotoSoap uses Photos permission for local review and iOS shows the final deletion confirmation.
