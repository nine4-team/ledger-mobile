---
work_package_id: "WP01"
title: "macOS Platform Foundation"
lane: "planned"
dependencies: []
subtasks: ["T001", "T002", "T003", "T004", "T005", "T006", "T007"]
history:
  - date: "2026-02-28"
    event: "Created"
---

# WP01: macOS Platform Foundation

## Implementation Command

```bash
spec-kitty implement WP01
```

## Objective

Make the existing iOS app compile and launch on macOS as a native SwiftUI app. After this WP, a developer can build the Ledger target for macOS, sign in with Google, and see the existing UI (even if layouts aren't optimized for wide screens yet).

## Context

- **Current state**: `LedgeriOS` target supports iOS only. 4 files reference UIKit APIs.
- **Target state**: Single multi-platform target supports both iOS and macOS.
- **Platform targets**: iOS 18+, macOS 15+
- **Key constraint**: iPhone behavior must be identical after changes. All `#if os()` conditionals must preserve existing iOS code paths unchanged.

### Files to modify

| File | Change |
|------|--------|
| `LedgeriOS.xcodeproj/project.pbxproj` | Add macOS destination, update SUPPORTED_PLATFORMS |
| `LedgeriOS/Auth/AuthManager.swift` | Remove UIKit import, remove UIViewController param, use platformSignIn() |
| `LedgeriOS/Auth/SignInView.swift` | Remove UIWindowScene lookup, call simplified AuthManager API |
| `LedgeriOS/Views/Reports/ReportPDFSharing.swift` | Wrap UIActivityViewController in #if os(iOS) |
| `LedgeriOS/Views/Projects/ProjectDetailView.swift` | Wrap UIActivityViewController in #if os(iOS) |

### Files to create

| File | Purpose |
|------|---------|
| `LedgeriOS/Platform/PlatformPresenting.swift` | GoogleSignIn platform abstraction |
| `Ledger.entitlements` (or `LedgeriOS/LedgeriOS.entitlements`) | macOS App Sandbox |

---

## Subtasks

### T001: Add macOS as Supported Destination

**Purpose**: Enable the Xcode project to build for macOS.

**Steps**:
1. In Xcode, select the `LedgeriOS` target → General → Supported Destinations
2. Add "macOS" as a supported destination (this adds `macosx` to `SUPPORTED_PLATFORMS`)
3. Set macOS deployment target to 15.0 in Build Settings
4. Ensure all SPM dependencies (Firebase, GoogleSignIn) resolve for macOS — they already support macOS natively, but a clean resolve may be needed

**What NOT to do**:
- Do NOT rename the target from `LedgeriOS` to `Ledger` in this WP — that's a separate concern and risks breaking the project file
- Do NOT create a separate macOS target — this is a single multi-platform target

**Validation**:
- [ ] `SUPPORTED_PLATFORMS` includes `macosx` in build settings
- [ ] macOS deployment target is set to 15.0
- [ ] SPM packages resolve without errors

---

### T002: Create macOS App Sandbox Entitlements

**Purpose**: macOS apps require App Sandbox for distribution. Firebase requires outgoing network connections.

**Steps**:
1. Create an entitlements file for macOS at the project level
2. Add the following entitlements:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

3. In Xcode, assign this entitlements file to the macOS build only (under Build Settings → Code Signing Entitlements, set per-platform if needed)

**Why network.client is required**: Without `com.apple.security.network.client`, all Firebase network calls fail with "Host name resolution failed" in sandboxed macOS builds.

**Validation**:
- [ ] Entitlements file exists with App Sandbox and network.client
- [ ] Entitlements file is referenced in macOS build settings

---

### T003: Create Platform/PlatformPresenting.swift

**Purpose**: Abstract the platform difference in GoogleSignIn presentation. iOS uses UIViewController, macOS uses NSWindow.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Platform/` directory
2. Create `PlatformPresenting.swift` with the following implementation:

```swift
// Platform/PlatformPresenting.swift
import GoogleSignIn

#if os(iOS)
import UIKit

/// Gets the presenting view controller for GoogleSignIn on iOS.
@MainActor
func platformPresentingAnchor() throws -> UIViewController {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first,
          let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
    else {
        throw PlatformError.noPresentingContext
    }
    return rootVC
}

#elseif os(macOS)
import AppKit

/// Gets the presenting window for GoogleSignIn on macOS.
@MainActor
func platformPresentingAnchor() throws -> NSWindow {
    guard let window = NSApplication.shared.keyWindow else {
        throw PlatformError.noPresentingContext
    }
    return window
}

#endif

enum PlatformError: LocalizedError {
    case noPresentingContext

    var errorDescription: String? {
        "No presenting context available for sign-in."
    }
}
```

**Key decisions**:
- Named `platformPresentingAnchor()` (not `platformSignIn()`) because it returns the anchor — the AuthManager still handles the actual sign-in call
- `@MainActor` isolation matches AuthManager's isolation
- Error type is shared across platforms

**Validation**:
- [ ] File compiles on both iOS and macOS
- [ ] Returns UIViewController on iOS, NSWindow on macOS

---

### T004: Refactor AuthManager for Cross-Platform GoogleSignIn

**Purpose**: Remove UIKit dependency from AuthManager. The current `signInWithGoogle(presentingViewController:)` takes a UIViewController, which doesn't exist on macOS.

**Current code** (`AuthManager.swift:1,39-58`):
```swift
import UIKit  // ← Must be removed/conditioned

func signInWithGoogle(presentingViewController: UIViewController) async throws {
    // ... uses presentingViewController for GIDSignIn
}
```

**Target code**:
```swift
// No UIKit import at the top level

func signInWithGoogle() async throws {
    errorMessage = nil

    let anchor = try platformPresentingAnchor()
    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: anchor)

    guard let idToken = result.user.idToken?.tokenString else {
        throw NSError(
            domain: "AuthManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."]
        )
    }

    let accessToken = result.user.accessToken.tokenString
    let credential = GoogleAuthProvider.credential(
        withIDToken: idToken,
        accessToken: accessToken
    )

    try await Auth.auth().signIn(with: credential)
}
```

**Steps**:
1. Remove `import UIKit` from AuthManager.swift entirely
2. Change method signature from `signInWithGoogle(presentingViewController: UIViewController)` to `signInWithGoogle()` (no parameter)
3. Inside the method, call `let anchor = try platformPresentingAnchor()` from PlatformPresenting.swift
4. Pass `anchor` to `GIDSignIn.sharedInstance.signIn(withPresenting:)` — the GoogleSignIn SDK overloads this method for both UIViewController and NSWindow
5. Keep all credential handling and Firebase auth unchanged

**Important**: The GoogleSignIn-iOS SDK's `signIn(withPresenting:)` has separate overloads for `UIViewController` (iOS) and `NSWindow` (macOS). Since `platformPresentingAnchor()` returns the correct type per platform, the compiler selects the right overload automatically.

**Validation**:
- [ ] AuthManager.swift has no `import UIKit`
- [ ] `signInWithGoogle()` takes no parameters
- [ ] Compiles on both iOS and macOS

---

### T005: Update SignInView for Platform-Agnostic Auth

**Purpose**: SignInView currently does its own UIWindowScene lookup to get the presenting view controller. With the refactored AuthManager, this is no longer needed.

**Current code** (`SignInView.swift:132-150`):
```swift
private func signInWithGoogle() {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first,
          let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
    else { return }

    isLoading = true
    errorMessage = nil

    Task {
        do {
            try await authManager.signInWithGoogle(presentingViewController: rootVC)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

**Target code**:
```swift
private func signInWithGoogle() {
    isLoading = true
    errorMessage = nil

    Task {
        do {
            try await authManager.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

**Steps**:
1. Remove the `UIApplication.shared.connectedScenes` lookup entirely
2. Remove the `guard` for windowScene/rootVC
3. Call `authManager.signInWithGoogle()` with no arguments
4. Keep error handling and loading state unchanged

**Validation**:
- [ ] SignInView.swift has no UIKit references
- [ ] Google Sign-In button still works on iOS
- [ ] Compiles on macOS

---

### T006: Wrap UIKit Sharing Code with Platform Conditionals

**Purpose**: Two files use `UIActivityViewController` for sharing (PDF reports and CSV export). This UIKit class doesn't exist on macOS.

**File 1: ReportPDFSharing.swift** (`line 27-34`):
```swift
guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = scene.windows.first?.rootViewController else { return }

let activityVC = UIActivityViewController(
    activityItems: [tempURL],
    applicationActivities: nil
)
rootVC.present(activityVC, animated: true)
```

**File 2: ProjectDetailView.swift** (`line 157-161`):
```swift
guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = scene.windows.first?.rootViewController else { return }

let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
rootVC.present(activityVC, animated: true)
```

**Steps**:
1. In both files, wrap the UIKit sharing code in `#if os(iOS)`:

```swift
#if os(iOS)
guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = scene.windows.first?.rootViewController else { return }

let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
rootVC.present(activityVC, animated: true)
#elseif os(macOS)
// Use NSSharingServicePicker for macOS sharing
if let window = NSApplication.shared.keyWindow {
    let picker = NSSharingServicePicker(items: [tempURL])
    // Present from a reasonable location — the window's content view
    if let contentView = window.contentView {
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }
}
#endif
```

2. Add `#if canImport(UIKit)` / `#if canImport(AppKit)` imports if the file uses UIKit types at the top level

**Note**: A more complete macOS sharing solution (SwiftUI `ShareLink`) could replace this later, but `#if os()` with `NSSharingServicePicker` is the minimal change to unblock macOS compilation.

**Validation**:
- [ ] ReportPDFSharing.swift compiles on macOS
- [ ] ProjectDetailView.swift compiles on macOS
- [ ] iOS sharing behavior unchanged

---

### T007: Build Verification

**Purpose**: Verify the macOS target compiles and the auth flow works end-to-end.

**Steps**:
1. Build the target for macOS (`Product → Build` or `xcodebuild -destination 'platform=macOS'`)
2. Resolve any remaining compilation errors (there may be additional UIKit references not caught in the audit)
3. If possible, launch on macOS and verify:
   - App window appears
   - Sign-in screen renders
   - Google Sign-In button triggers the macOS native flow (requires GoogleService-Info.plist for macOS bundle ID — if not available, verify compilation only)

**Known limitation**: Full auth testing requires a macOS `GoogleService-Info.plist` registered in Firebase Console. If not yet registered, this subtask verifies compilation only. Auth flow testing is deferred to manual QA.

**Validation**:
- [ ] `xcodebuild build -scheme LedgeriOS -destination 'platform=macOS'` succeeds
- [ ] No UIKit symbols referenced in macOS build
- [ ] Zero warnings related to platform availability

---

## Definition of Done

- [ ] macOS target added to Xcode project
- [ ] App Sandbox entitlements created with network.client
- [ ] AuthManager has no UIKit dependency — uses PlatformPresenting.swift
- [ ] SignInView calls simplified signInWithGoogle() with no UIViewController
- [ ] UIActivityViewController usage wrapped in #if os(iOS)
- [ ] Project builds successfully for both iOS and macOS
- [ ] No changes to iPhone behavior

## Risks

| Risk | Mitigation |
|------|------------|
| Additional UIKit references not caught in audit | T007 build verification will surface them; fix with #if conditionals |
| SPM packages fail to resolve for macOS | Clean SPM cache, re-resolve. Firebase + GoogleSignIn both declare macOS support. |
| GoogleService-Info.plist missing for macOS | Compilation doesn't require it. Auth flow testing deferred until Firebase Console registration. |
| GIDSignIn API differences on macOS | SDK provides matching overloads for NSWindow. PlatformPresenting returns correct type. |

## Reviewer Guidance

1. Verify `import UIKit` does not appear anywhere outside `#if` conditionals
2. Verify iPhone UI is pixel-identical (no changes to iOS code paths)
3. Check that entitlements include both sandbox and network.client
4. Confirm PlatformPresenting.swift compiles on both platforms
