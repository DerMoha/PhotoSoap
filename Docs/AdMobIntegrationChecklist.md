# AdMob Integration Checklist

PhotoSoap now uses a single non-personalized AdMob banner placed directly below the current review photo. Ad-free access still disables that banner after a purchase or after deleting 2000 photos.

## SDK wiring

- Keep the Google Mobile Ads SDK linked in `PhotoSoap.xcodeproj`.
- Initialize the SDK during app launch before loading the review banner.
- Keep the production AdMob app ID and review banner unit ID in `PhotoSoap/Info.plist`.

## Placement behavior

- Show only one banner in the review flow, directly below the active photo card.
- Do not show ads on the Stats or Achievements tabs.
- Do not present interstitial ads.
- Continue suppressing the review banner whenever ad-free access is purchased or earned.

## ATT and privacy

- Keep ads non-personalized and do not request App Tracking Transparency unless the ad strategy changes.
- Leave `NSPrivacyTracking` set to `false` in `PhotoSoap/PrivacyInfo.xcprivacy` unless tracking is intentionally introduced later.
- Verify the shipped privacy manifests from Google Mobile Ads and the app's own `PhotoSoap/PrivacyInfo.xcprivacy` still match the final binary.
- Complete the App Store privacy questionnaire to reflect optional anonymous analytics, non-personalized ads, and the fact that photo contents are never sent for analytics.

## Current privacy posture

- `PhotoSoap/PrivacyInfo.xcprivacy` currently declares no tracking, no collected data at the app level, and only `UserDefaults` accessed API usage.
- `PhotoSoap/Info.plist` contains only Photos permission strings plus the AdMob app ID and single review-banner unit ID.
- The app's own analytics are optional, off by default, and do not send photo contents, asset IDs, or location data.
- The first-run welcome sheet explains optional analytics, the single review banner, and the free loyalty unlock after 2000 deleted photos.

## Embedded SDK manifest notes

- The embedded Google Mobile Ads framework privacy manifest declares collection related to advertising data, product interaction, device ID, coarse location, crash data, performance data, and other diagnostic data.
- The embedded User Messaging Platform privacy manifest declares coarse location, product interaction, and performance data for app functionality.
- Treat those embedded manifests as the floor for your App Store privacy answers, even if PhotoSoap itself does not send photo contents or run its own network analytics.
- Re-check the release archive before submission in case a Google SDK update changes any declared data categories.

## App Store Connect starting point

- Tracking: start with `No` because PhotoSoap does not request ATT and is intended to use non-personalized ads only.
- Photos or videos: `No` for collected data sent off-device by the app, because PhotoSoap reviews the library locally and the app's own analytics do not transmit photo contents.
- Purchases: review carefully during submission; StoreKit powers ad-free unlocks, but PhotoSoap does not maintain its own purchase profile beyond entitlement state.
- Identifiers and usage data: expect to disclose the categories declared by the embedded Google SDK manifests.
- Privacy policy text should clearly say that PhotoSoap may show one non-personalized ad while reviewing, optional analytics are off by default, and ad-free unlock is available by purchase or after 2000 deleted photos.

## Final submission check

- Archive a release build and inspect the final embedded privacy manifests, not just the debug simulator build.
- Confirm App Store Connect privacy answers still match the exact Google SDK version in the archive.
- Confirm the welcome sheet, Stats privacy card, and ad-free sheet all describe the same privacy and monetization behavior.
- If ATT, personalized ads, or additional analytics are added later, update `PhotoSoap/PrivacyInfo.xcprivacy`, onboarding copy, and App Store Connect answers together.

## Release safety

- Use test ad requests for development and TestFlight before the production rollout is approved in AdMob.
- Verify buy, restore, and loyalty unlock paths still suppress ads.
- Confirm the banner appears only below the current review photo and that the space collapses when ads are disabled.
- Confirm the first-run welcome sheet explains analytics, the single banner placement, and the free loyalty unlock at 2000 deleted photos.
