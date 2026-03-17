# PhotoSoap Agent Guide
This file is for agentic coding assistants working in this repository.
Keep guidance short, practical, and aligned with the current SwiftUI codebase.
## Project Snapshot
- iOS app built with SwiftUI, SwiftData, Photos, and StoreKit-related services.
- Main app target and shared scheme: `PhotoSoap`.
- The project uses `PhotoSoap.xcworkspace` (CocoaPods). Always use the workspace, not the `.xcodeproj` directly.
- No XCTest target is configured today, even though the shared scheme has a `TestAction`.
- Historical references to `Bommel` are stale and only appear in user-specific Xcode metadata and git history.
## Repository Layout
- `PhotoSoap/PhotoSoapApp.swift`: app entry, model container bootstrap, migration helpers.
- `PhotoSoap/Models/`: SwiftData models and small domain enums.
- `PhotoSoap/Services/`: photo library, gamification, and purchase services.
- `PhotoSoap/ViewModels/`: lightweight presentation helpers.
- `PhotoSoap/Views/`: screens and flow-level SwiftUI views.
- `PhotoSoap/Views/Components/`: reusable UI pieces.
- `PhotoSoap/Utilities/`: extensions and general helpers.
- `PhotoSoap/Assets.xcassets/`: colors, images, and symbols.
- `PhotoSoap.xcodeproj/`: Xcode project, shared scheme, and build settings.
- `Podfile` / `Podfile.lock`: CocoaPods dependency configuration (Google Mobile Ads SDK).
- `Pods/`: CocoaPods-managed dependencies (not committed to git).
## Build, Run, Test
Use Xcode for interactive work, or `xcodebuild` for scripted verification.
### Shared scheme
```bash
xcodebuild -list -project PhotoSoap.xcodeproj
```
### Build for simulator
```bash
xcodebuild -workspace PhotoSoap.xcworkspace -scheme PhotoSoap -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
### Build for generic iOS device
```bash
xcodebuild -workspace PhotoSoap.xcworkspace -scheme PhotoSoap -configuration Release -destination 'generic/platform=iOS' build
```
### Run in Xcode
```bash
open PhotoSoap.xcworkspace
```
### Test all
- There is no XCTest bundle in the project today, so `xcodebuild test` will not execute app tests yet.
- If a test target is added later, use:
```bash
xcodebuild test -workspace PhotoSoap.xcworkspace -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
### Run a single test
- Single-test execution is not available yet because no test target exists.
- After adding a shared XCTest target such as `PhotoSoapTests`, use:
```bash
xcodebuild test -workspace PhotoSoap.xcworkspace -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PhotoSoapTests/SomeTestCase/testExample
```
### Analyze
```bash
xcodebuild -workspace PhotoSoap.xcworkspace -scheme PhotoSoap analyze
```
### Lint / format
- No `SwiftLint`, `SwiftFormat`, or other lint config is checked in.
- Use Xcode formatting (`Editor > Structure > Re-Indent`, or `Ctrl+I`) and match existing file style.
- If you add lint or format tooling, update this guide with the exact commands.
### Environment note
- In this workspace, `xcodebuild -list` currently fails before project inspection because a local Xcode plug-in is missing and suggests `xcodebuild -runFirstLaunch`.
- Treat that as a machine-specific issue, not a repository configuration rule.
## Agent Instructions Sources
- Root agent guide: `AGENTS.md`.
- No `.cursorrules` file found.
- No `.cursor/rules/` directory found.
- No `.github/copilot-instructions.md` file found.
## Swift Code Style
### Imports
- Keep imports at the top of the file with one blank line after the import block.
- Prefer consistent Apple-framework ordering, usually UI frameworks first, then data/system frameworks.
- Common patterns here include `SwiftUI`, `SwiftData`, `Photos`, `UIKit`, `Foundation`, and `Combine`.
- Remove unused imports when editing a file.
### Formatting
- Use 4-space indentation and one statement per line.
- Favor trailing-closure syntax in SwiftUI builders.
- Use blank lines to separate logical sections, not every individual statement.
- Prefer extracted `private var`, `private func`, and `@ViewBuilder` helpers over oversized `body` blocks.
- Keep `#Preview` at the bottom of SwiftUI view files.
- Use `// MARK: - Section` for meaningful section breaks.
### Naming
- Types, protocols, and enums: PascalCase.
- Properties, functions, and enum cases: lowerCamelCase.
- Boolean names should read as predicates, usually starting with `is`, `has`, or `should`.
- Prefer singular nouns for model types such as `Photo`, `UserStats`, and `ReviewedPhoto`.
- Use descriptive names for state flags instead of short abbreviations.
### Types and structure
- SwiftUI screens and components are `struct` types conforming to `View`.
- View models are `@MainActor` classes conforming to `ObservableObject`.
- UI-facing services are also typically `@MainActor` `ObservableObject` classes.
- SwiftData entities use `@Model` classes with explicit initializers.
- Keep one primary type per file unless a tiny helper type is tightly coupled to it.
- Prefer `private` for caches, constants, and helpers not used across files.
### SwiftUI conventions
- Use property wrappers intentionally: `@State`, `@StateObject`, `@ObservedObject`, `@Environment`, `@Query`, `@AppStorage`, and `@Bindable` where appropriate.
- Keep view bodies declarative and move substantial subtrees into private computed properties or helper functions.
- Use `NavigationStack`, `TabView`, `ZStack`, and other containers in the same style already present.
- Use `Task {}` to bridge async service calls from button taps and lifecycle hooks.
- Keep previews simple and local, usually with in-memory model containers where needed.
### SwiftData conventions
- Define explicit initializers instead of relying on many inline default property values.
- Keep derived values as computed properties, not persisted storage, when practical.
- Query models with `FetchDescriptor`, `#Predicate`, and `SortDescriptor`.
- Preserve migration helpers and deprecated compatibility code unless you are intentionally removing legacy behavior.
### Error handling and concurrency
- Prefer `guard` and early returns for invalid state.
- Use `enum` errors conforming to `LocalizedError` for user-facing failures.
- Wrap Photos, persistence, and async operations with `do/catch` when failure is expected.
- Surface alerts and UI messaging from `error.localizedDescription` where that pattern already exists.
- Use `fatalError` only for unrecoverable bootstrap failures, such as model container initialization.
- Prefer `async`/`await`; use `withCheckedContinuation` or `withCheckedThrowingContinuation` when bridging callbacks.
- For delegate or nonisolated callbacks, hop back to the main actor before mutating observable state.
### Logging and comments
- Keep logging lightweight and prefix debug prints with `PhotoSoap:`.
- Avoid noisy logs inside tight loops or rapidly updating UI paths.
- Add comments only when a block is non-obvious.
- Prefer clear naming and extracted helpers over explanatory comments.
- Preserve meaningful `// MARK:` sections and remove stale or redundant comments when touching nearby code.
## Working Patterns By Layer
### App bootstrap
- `PhotoSoapApp` owns model container setup and migration helpers.
- Bootstrap code may clear oversized stores, run migrations, and fail fast if the persistent stack cannot initialize.
### Models
- Models are mutable `@Model` classes with focused methods for domain updates.
- Keep formatting helpers, such as byte-count display, as computed properties.
- Use availability annotations when deprecating legacy APIs.
### Services
- Services own side effects, business rules, Photos access, and persistence fetches.
- Publish only state that views consume.
- Keep caches, thresholds, and implementation details private.
- Prefer narrow methods like `processPhotoReview(...)` or `getNextPhoto(...)` over broad controller-style APIs.
### View models
- View models are lightweight presentation adapters.
- Expose computed display items and formatting helpers rather than mirroring model state unnecessarily.
### Views
- Extract large sections into `private var` or `private func` helpers.
- Use `@ViewBuilder` for conditional fragments that would otherwise clutter `body`.
- Maintain platform-native styling patterns already used in the app, including system colors and standard SwiftUI typography.
## Practical Guidance For Agents
- Check for unrelated working tree changes before editing; do not revert user changes.
- Match the style of the file you are touching rather than imposing a new pattern.
- Prefer surgical edits over broad refactors unless the task requires larger cleanup.
- If you add a test target, make sure the scheme remains shared so CI and agents can discover it.
- When documenting commands in future updates, prefer copy-pasteable commands with explicit project, scheme, and destination values.
## Handy Commands
```bash
open PhotoSoap.xcworkspace
xcodebuild -list -project PhotoSoap.xcodeproj
xcodebuild -workspace PhotoSoap.xcworkspace -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -workspace PhotoSoap.xcworkspace -scheme PhotoSoap analyze
xcodebuild test -workspace PhotoSoap.xcworkspace -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PhotoSoapTests/SomeTestCase/testExample
```
## Keep This File Updated
- Update this guide when adding test targets, linting, formatting tools, CI workflows, or new shared schemes.
- Remove stale references when project structure changes.
- Keep the document concise enough for fast agent scanning, but specific enough to prevent guesswork.
