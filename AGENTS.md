# PhotoSoap Agent Guide
This file is for agentic coding assistants working in this repository.
Keep guidance short, practical, and aligned with the current SwiftUI codebase.
## Project Snapshot
- iOS app built with SwiftUI, SwiftData, Photos, and a small set of local app services.
- Main app target and shared scheme: `PhotoSoap`.
- Open `PhotoSoap.xcodeproj` directly for local development; the workspace no longer has dependency-specific setup.
- A `PhotoSoapTests` XCTest target is configured in the project.
## Repository Layout
- `PhotoSoap/PhotoSoapApp.swift`: app entry, model container bootstrap, migration helpers.
- `PhotoSoap/Models/`: SwiftData models and small domain enums.
- `PhotoSoap/Services/`: photo library, gamification, analytics, haptics, and aggregate metrics services.
- `PhotoSoap/ViewModels/`: lightweight presentation helpers.
- `PhotoSoap/Views/`: screens and flow-level SwiftUI views.
- `PhotoSoap/Views/Components/`: reusable UI pieces.
- `PhotoSoap/Utilities/`: extensions and general helpers.
- `PhotoSoap/Assets.xcassets/`: colors, images, and symbols.
- `PhotoSoap.xcodeproj/`: Xcode project, shared scheme, and build settings.
## Build, Run, Test
Use Xcode for interactive work, or `xcodebuild` for scripted verification.
### Shared scheme
```bash
xcodebuild -list -project PhotoSoap.xcodeproj
```
### Build for simulator
```bash
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16e' build
```
### Build for generic iOS device
```bash
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -configuration Release -destination 'generic/platform=iOS' build
```
### Run in Xcode
```bash
open PhotoSoap.xcodeproj
```
### Test all
```bash
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 16e'
```
### Run a single test
```bash
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:PhotoSoapTests/SomeTestCase/testExample
```
### Analyze
```bash
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap analyze
```
### CI
- GitHub Actions workflow: `.github/workflows/ios.yml`, triggered by pushes, pull requests, and manual runs.
- Uses macOS 15 with Xcode 26.3 and an available iPhone simulator to build and run all tests without signing.
- Test result bundles and build logs are uploaded as `ios-test-results` artifacts.
### Lint / format
- No `SwiftLint`, `SwiftFormat`, or other lint config is checked in.
- Use Xcode formatting (`Editor > Structure > Re-Indent`, or `Ctrl+I`) and match existing file style.
- If you add lint or format tooling, update this guide with the exact commands.
### Environment note
- In this environment, `xcodebuild -list` may fail before project inspection because a local Xcode plug-in is missing and suggests `xcodebuild -runFirstLaunch`.
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
open PhotoSoap.xcodeproj
xcodebuild -list -project PhotoSoap.xcodeproj
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 16e' build
xcodebuild -project PhotoSoap.xcodeproj -scheme PhotoSoap analyze
xcodebuild test -project PhotoSoap.xcodeproj -scheme PhotoSoap -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:PhotoSoapTests/SomeTestCase/testExample
```
## Keep This File Updated
- Update this guide when adding test targets, linting, formatting tools, CI workflows, or new shared schemes.
- Remove stale references when project structure changes.
- Keep the document concise enough for fast agent scanning, but specific enough to prevent guesswork.
