# AdMob Integration Checklist

PhotoSoap now includes an ad coordinator scaffold, test identifiers in `PhotoSoap/Info.plist`, and paywall UI wiring. Before shipping real ads, finish the steps below.

## SDK wiring

- Add the Google Mobile Ads SDK to `PhotoSoap.xcodeproj`.
- Initialize the SDK during app launch before loading any placements.
- Replace the test identifiers in `PhotoSoap/Info.plist` with production values from AdMob.

## Placement rollout

- Start with `statsBanner` and `achievementsBanner`.
- Keep `reviewCompletionInterstitial` limited to natural pauses after a batch finishes.
- Continue suppressing all placements whenever ad-free access is purchased or earned.

## ATT and privacy

- Keep `NSUserTrackingUsageDescription` aligned with the final ad experience.
- Revisit `PhotoSoap/PrivacyInfo.xcprivacy` after the SDK is linked and declare any collected data or tracking behavior required by Google Mobile Ads.
- Add the App Store privacy questionnaire answers that match the final SDK configuration.

## Release safety

- Use only test ads for development and TestFlight until production IDs are approved.
- Verify buy, restore, and loyalty unlock paths still suppress ads.
- Confirm ads do not appear in the swipe-review flow.
