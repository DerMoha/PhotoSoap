# PhotoSoap Agent Guide

This file is for agentic coding assistants working in this repository.
Keep guidance concise and aligned with the current codebase.

## Project Overview
- SwiftUI + SwiftData iOS app for photo review and gamification.
- Primary target/scheme: PhotoSoap (shared).
- Secondary shared scheme: Bommel (legacy/unused).

## Repository Layout
- PhotoSoap/PhotoSoapApp.swift: app entry, model container setup.
- PhotoSoap/Models/: SwiftData models and enums.
- PhotoSoap/Services/: Photo library and gamification logic.
- PhotoSoap/ViewModels/: view model helpers.
- PhotoSoap/Views/: SwiftUI screens.
- PhotoSoap/Views/Components/: reusable view pieces.
- PhotoSoap/Utilities/: extensions, modifiers, utilities.
- PhotoSoap/Assets.xcassets/: app assets.
- PhotoSoap.xcodeproj/: Xcode project and schemes.

## Build, Run, Test
Use Xcode for interactive development, or xcodebuild for CI.

### List schemes
```bash
xcodebuild -list -project PhotoSoap.xcodeproj
```

### Build (simulator)
```bash
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Build (device, generic)
```bash
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -configuration Release -destination 'generic/platform=iOS' build
```

### Run
- Open the project: `open PhotoSoap.xcodeproj` and run the PhotoSoap scheme.
- Or `xcodebuild` + `xcrun simctl` if scripting a simulator run.

### Test (all)
- No XCTest targets are present today.
- If a test target is added (ex: PhotoSoapTests), run:
```bash
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test (single test)
```bash
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PhotoSoapTests/SomeTestCase/testExample
```
- Replace target/class/method with real XCTest names.

### Lint / Format
- No SwiftLint/SwiftFormat config is checked in.
- Use Xcode's formatter (Ctrl+I) and match existing SwiftUI style.

## Cursor / Copilot Rules
- No `.cursor/rules`, `.cursorrules`, or `.github/copilot-instructions.md` found.

## Code Style Guidelines

### Imports
- Keep imports at the top of the file with a single blank line after.
- Order Apple frameworks consistently (ex: SwiftUI, SwiftData, Photos).
- Avoid unused imports; remove when not needed.

### Formatting
- 4-space indentation, one statement per line.
- Prefer trailing closure syntax for SwiftUI builders.
- Use `// MARK: - Section` to group logical blocks.
- Keep view bodies readable via extracted `private var` sections.
- Place `#Preview` at the bottom of view files.

### Naming
- Types and protocols: PascalCase (`PhotoLibraryService`).
- Properties, methods, enum cases: lowerCamelCase.
- Boolean names start with `is`, `has`, `should`.
- Use singular nouns for model types (`Photo`, `UserStats`).

### SwiftUI Views
- Views are `struct` types conforming to `View`.
- Use `@State`, `@StateObject`, `@ObservedObject`, `@Environment` as needed.
- Extract complex layout pieces into `private var` or `private func` sections.
- Use `@ViewBuilder` helpers for conditional view fragments.
- Keep animations explicit with `withAnimation` or `.animation(..., value:)`.
- Use `NavigationStack`, `TabView`, `ZStack`, `LazyVGrid` per existing patterns.

### View Models
- View models are `@MainActor class` and `ObservableObject`.
- Expose read-only computed data where possible.
- Use small struct helpers for display items (ex: `StatItem`).

### Services
- Services touching UI state are `@MainActor` and `ObservableObject`.
- Keep side effects inside services (Photos, SwiftData fetches).
- Use `@Published` for any state consumed by views.
- Use `private` properties for caches and derived state.

### Data Models (SwiftData)
- Use `@Model` classes for persisted entities.
- Define explicit initializers with defaults.
- Store derived values as computed properties, not persisted fields.
- Use `FetchDescriptor` + `#Predicate` + `SortDescriptor` for queries.

### Error Handling
- Use `enum` errors conforming to `LocalizedError` for user-facing messages.
- Prefer `guard` + early return for invalid state.
- Use `do/catch` around persistence and Photos APIs.
- Surface errors with `error.localizedDescription` in alerts.
- Use `fatalError` only for unrecoverable bootstrap failures (model container init).

### Concurrency
- Use `async`/`await` for Photos and data operations.
- Keep UI mutations on the main actor.
- Use `Task { }` from UI actions to bridge async calls.
- Use `withCheckedThrowingContinuation` to wrap callback APIs.

### Logging
- Use lightweight `print` statements with a `PhotoSoap:` prefix.
- Avoid noisy logging in tight loops or repeated UI updates.

### Assets & Styling
- Store assets in `Assets.xcassets` and refer via `Image`/`Color` assets.
- Prefer system colors (`Color(.systemGroupedBackground)`) for platform fidelity.
- Keep typography consistent with existing `font(.headline)` style usage.

### File Organization
- Keep files focused: one primary type per file.
- Components live in `Views/Components` for reuse.
- Utilities belong in `Utilities/Extensions.swift` when broadly useful.

### Suggested Defaults for New Code
- New services: `@MainActor class`, `ObservableObject`, `@Published` state.
- New views: `struct`, `private` view sections, `#Preview` with sample data.
- New errors: `enum` with `LocalizedError` conformance.
- New SwiftData models: `@Model` classes with explicit init.

## Example Commands (Copy/Paste)
```bash
open PhotoSoap.xcodeproj
xcodebuild -list -project PhotoSoap.xcodeproj
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PhotoSoapTests/SomeTestCase/testExample
```

## Notes
- If you add tests, ensure the scheme is shared so CI can discover it.
- Keep new code consistent with existing SwiftUI patterns and sectioning.
- Update this guide when adding linting, CI, or new targets.
