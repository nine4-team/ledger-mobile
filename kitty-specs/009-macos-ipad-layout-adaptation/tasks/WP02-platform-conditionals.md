---
work_package_id: WP02
title: Platform Conditional Compilation
lane: planned
dependencies:
- WP01
subtasks:
- T005
- T006
- T007
- T008
- T009
- T010
phase: Phase 1 - Foundation
assignee: ''
agent: ''
shell_pid: ''
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-03-01T05:27:35Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP02 – Platform Conditional Compilation

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

> **Populated by `/spec-kitty.review`**

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

Depends on WP01 (macOS target must exist).

---

## Objectives & Success Criteria

- All UIKit-only code is wrapped with `#if canImport(UIKit)` / `#if canImport(AppKit)` conditionals
- A new `Platform/PlatformPresenting.swift` file abstracts GoogleSignIn presentation for iOS (UIViewController) and macOS (NSWindow)
- `AuthManager.swift` no longer directly references UIKit types
- `ReportPDFSharing.swift` compiles on macOS with appropriate fallbacks
- `LedgerApp.swift` uses the correct application delegate adaptor per platform
- New layout dimension constants exist in `Dimensions.swift`
- The project builds and launches on macOS, reaching the auth screen without crashes

## Context & Constraints

- **Spec**: FR-1 (Native macOS Target), FR-8 (Cross-Platform GoogleSignIn)
- **Plan**: Phase A (Project Setup & Platform Foundation)
- **Research**: §3 (GoogleSignIn macOS), §4 (Firebase macOS), §9 (Codebase Audit)
- **Codebase audit findings**:
  - `AuthManager.swift` — only file importing UIKit directly (for GoogleSignIn UIViewController)
  - `ReportPDFSharing.swift` — uses `UIScreen.main.scale` and `UIActivityViewController`
  - `LedgerApp.swift` — uses `@UIApplicationDelegateAdaptor`
  - Zero existing `#if os()` or `#if canImport()` usage — clean slate
- **Constraint**: Use `#if canImport(UIKit)` / `#if canImport(AppKit)` (not `#if os()`) for framework availability checks. Use `#if os(macOS)` / `#if os(iOS)` only for OS-specific behavior that isn't tied to framework availability.

## Subtasks & Detailed Guidance

### Subtask T005 – Wrap UIKit in AuthManager.swift

- **Purpose**: `AuthManager.swift` imports UIKit for GoogleSignIn's `UIViewController`-based presentation. macOS uses `NSWindow` instead. Wrap platform-specific code so both platforms compile.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Auth/AuthManager.swift` to understand current GoogleSignIn flow
  2. The current `signInWithGoogle(presentingViewController:)` method takes a `UIViewController` parameter
  3. Remove the UIKit import and UIViewController parameter
  4. Instead, call the new `platformSignIn()` function from `PlatformPresenting.swift` (T006)
  5. The AuthManager method becomes platform-agnostic:
     ```swift
     func signInWithGoogle() async throws {
         let result = try await platformSignIn()
         // Process GIDSignInResult...
     }
     ```
  6. Any other UIKit references in the file (if any) should be wrapped in `#if canImport(UIKit)`
  7. Verify the file compiles on both platforms
- **Files**: `LedgeriOS/LedgeriOS/Auth/AuthManager.swift`
- **Parallel?**: Coupled with T006 — do together.
- **Notes**: The caller (`SignInView`) currently passes the presenting view controller. After this change, the caller just calls `signInWithGoogle()` without a parameter.

### Subtask T006 – Create Platform/PlatformPresenting.swift

- **Purpose**: Provide a platform-agnostic function that handles GoogleSignIn presentation, abstracting the iOS/macOS difference.
- **Steps**:
  1. Create directory: `LedgeriOS/LedgeriOS/Platform/`
  2. Create file: `LedgeriOS/LedgeriOS/Platform/PlatformPresenting.swift`
  3. Implementation:
     ```swift
     import GoogleSignIn

     #if canImport(UIKit)
     import UIKit

     @MainActor
     func platformSignIn() async throws -> GIDSignInResult {
         guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController else {
             throw AuthError.noPresentingContext
         }
         return try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
     }
     #elseif canImport(AppKit)
     import AppKit

     @MainActor
     func platformSignIn() async throws -> GIDSignInResult {
         guard let window = NSApplication.shared.keyWindow else {
             throw AuthError.noPresentingContext
         }
         return try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
     }
     #endif
     ```
  4. Add `AuthError.noPresentingContext` case if it doesn't already exist (check AuthManager for existing error enum)
  5. Ensure the file is added to the Xcode project (should be automatic if in the project directory)
- **Files**: `LedgeriOS/LedgeriOS/Platform/PlatformPresenting.swift` (new file)
- **Parallel?**: Coupled with T005 — do together.
- **Notes**: The `GIDSignInResult` type is the same on both platforms. Only the `withPresenting:` parameter type differs.

### Subtask T007 – Wrap UIApplicationDelegateAdaptor in LedgerApp.swift

- **Purpose**: `@UIApplicationDelegateAdaptor` is iOS-only. macOS uses `@NSApplicationDelegateAdaptor`. Wrap with platform conditionals.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/LedgerApp.swift`
  2. Find the `@UIApplicationDelegateAdaptor` usage
  3. Wrap it:
     ```swift
     #if canImport(UIKit)
     @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
     #endif
     ```
  4. If the AppDelegate does Firebase configuration, consider whether macOS needs an equivalent `@NSApplicationDelegateAdaptor`. If Firebase is configured elsewhere (e.g., in `init()` or `.task`), this may not be needed.
  5. Also check for `UIApplication.shared.connectedScenes` or other UIKit-specific code in LedgerApp.swift and wrap those similarly
  6. Verify the file compiles on both platforms
- **Files**: `LedgeriOS/LedgeriOS/LedgerApp.swift`
- **Parallel?**: Yes — independent of T005/T006.
- **Notes**: If Firebase configuration happens in the AppDelegate, you'll need an NSApplicationDelegate on macOS. Check where `FirebaseApp.configure()` is called.

### Subtask T008 – Wrap UIScreen/UIApplication in ReportPDFSharing.swift

- **Purpose**: `ReportPDFSharing.swift` uses `UIScreen.main.scale` for PDF rendering and `UIActivityViewController` for sharing. These don't exist on macOS.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/Reports/ReportPDFSharing.swift`
  2. Find `UIScreen.main.scale` usage and wrap:
     ```swift
     #if canImport(UIKit)
     renderer.scale = UIScreen.main.scale
     #elseif canImport(AppKit)
     renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
     #endif
     ```
  3. Find `UIActivityViewController` usage and wrap:
     ```swift
     #if canImport(UIKit)
     // Existing UIActivityViewController sharing code
     #elseif canImport(AppKit)
     // Use NSSharingServicePicker for macOS sharing
     let picker = NSSharingServicePicker(items: [pdfData])
     // Present picker...
     #endif
     ```
  4. If the macOS sharing implementation is complex, it's acceptable to stub it out (e.g., save to file via NSSavePanel) and refine later
  5. Verify the file compiles on both platforms
- **Files**: `LedgeriOS/LedgeriOS/Views/Reports/ReportPDFSharing.swift`
- **Parallel?**: Yes — independent of other subtasks.
- **Notes**: PDF rendering with `ImageRenderer` works on both platforms. Only the scale and sharing mechanism differ.

### Subtask T009 – Add Layout Constants to Dimensions.swift

- **Purpose**: Provide shared constants for adaptive layout widths used by WP06 and WP07.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Theme/Dimensions.swift`
  2. Add new constants (as per data-model.md):
     ```swift
     extension Dimensions {
         /// Maximum width for content in list/detail views (prevents stretching on wide screens)
         static let contentMaxWidth: CGFloat = 720

         /// Maximum width for form sheets on macOS
         static let formMaxWidth: CGFloat = 560

         /// Minimum card width for responsive grid calculation
         static let cardMinWidth: CGFloat = 320
     }
     ```
  3. These are pure constants — no platform branching needed
  4. Values chosen for readability: 720pt is approximately the width of a comfortable reading column on a large display
- **Files**: `LedgeriOS/LedgeriOS/Theme/Dimensions.swift`
- **Parallel?**: Yes — independent of all other subtasks.
- **Notes**: These constants will be consumed by `AdaptiveContentWidth` (WP06) and responsive grid calculations (WP07).

### Subtask T010 – Build and Launch on macOS

- **Purpose**: Verify the cumulative work of WP01 and WP02 results in a macOS app that compiles and launches.
- **Steps**:
  1. Build for macOS: `xcodebuild -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -destination 'platform=macOS'`
  2. If build fails, identify remaining UIKit references and wrap them with `#if canImport(UIKit)`
  3. Launch the macOS app
  4. Verify: App window appears → Auth screen is displayed → Google Sign-In button is visible
  5. If possible, test the sign-in flow (requires macOS GoogleService-Info.plist — may need to be deferred)
  6. Also build for iOS to verify no regressions: `xcodebuild -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e'`
- **Files**: N/A (build verification)
- **Parallel?**: No — must be done after T005-T009.
- **Notes**: If the macOS GoogleService-Info.plist is not yet registered in Firebase Console, sign-in won't work but the UI should still render. That's acceptable for this stage.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Additional UIKit references not caught by codebase audit | Build for macOS after each file change; compiler will flag remaining references |
| GoogleSignIn macOS API may behave differently | Isolated in PlatformPresenting.swift — easy to debug and fix |
| macOS sharing (NSSharingServicePicker) complexity | Stub with file save initially; refine in WP08 polish |
| Firebase configuration in AppDelegate may not work on macOS | Check if FirebaseApp.configure() needs @NSApplicationDelegateAdaptor |

## Review Guidance

- Build must succeed on BOTH iOS and macOS targets
- No raw UIKit types should appear outside `#if canImport(UIKit)` blocks
- `PlatformPresenting.swift` should be clean, focused, and minimal
- `Dimensions.swift` constants should match data-model.md values exactly
- macOS app should launch and show the auth screen (sign-in functionality may not work without macOS Firebase registration)

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP02 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
