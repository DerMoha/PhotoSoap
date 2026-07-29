# App Store privacy declaration

Use these answers in App Store Connect for PhotoSoap 1.0. They mirror the shipping privacy manifest and the optional analytics implementation.

## Data collected

Collection begins only after the user explicitly opts in. The app remains fully functional when the user declines.

| App Store data type | Purpose | Linked to the user | Tracking |
| --- | --- | --- | --- |
| Usage Data → Product Interaction | Analytics | Yes | No |
| Identifiers → Device ID | Analytics | Yes | No |

The Device ID is a random UUID created for this installation of PhotoSoap. It is not an advertising identifier, hardware identifier, account identifier, email address, or name. Apple treats it as linked because submitted daily usage totals are grouped by that persistent app-install identifier.

PhotoSoap does not collect or upload photos, videos, filenames, Photos asset identifiers, location data, contacts, advertising data, crash logs, or payment information. Photo-library content and review state remain on the device.

## Privacy manifest

- `NSPrivacyTracking`: No
- Tracking domains: None
- Required-reason API: User Defaults, reason `CA92.1` (app preferences)
- Collected data: Product Interaction and Device ID, both for Analytics, linked, and not used for tracking

## Review checks

- The App Store privacy answers must stay aligned with `PhotoSoap/PrivacyInfo.xcprivacy` and `PRIVACY.md`.
- Mark both collected data types as optional because every user can decline during onboarding or disable analytics in Settings without losing functionality.
- Do not declare Photos or Videos as collected: PhotoSoap processes them on-device and does not transmit them.
- The privacy-policy URL is `https://dermoha.github.io/PhotoSoap/privacy.html`.
