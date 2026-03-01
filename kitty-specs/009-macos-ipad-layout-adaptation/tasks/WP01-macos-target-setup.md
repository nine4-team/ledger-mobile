---
work_package_id: WP01
title: macOS Target Setup
lane: "for_review"
dependencies: []
base_branch: main
base_commit: 4651b59d566e91668ed2dd6b8ffe5090e7fe7707
created_at: '2026-03-01T05:57:58.919074+00:00'
subtasks:
- T001
- T002
- T003
- T004
phase: Phase 1 - Foundation
assignee: ''
agent: "claude"
shell_pid: "77935"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-03-01T05:27:35Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 – macOS Target Setup

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes.

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP01
```

No dependencies — this is the starting work package.

---

## Objectives & Success Criteria

- macOS is listed as a supported destination in the Xcode project
- App Sandbox entitlements file exists with network client capability for Firebase
- Info.plist contains `LSApplicationCategoryType` for macOS App Store categorization
- All SPM dependencies (Firebase Auth, Firestore, Storage, GoogleSignIn) resolve for the macOS target
- Build attempt for macOS starts compilation (UIKit-related build errors are expected and accepted at this stage — they are resolved in WP02)

## Context & Constraints

- **Project**: Ledger iOS — SwiftUI app at `LedgeriOS/LedgeriOS/`
- **Spec**: `kitty-specs/009-macos-ipad-layout-adaptation/spec.md` — FR-1 (Native macOS Target)
- **Plan**: `kitty-specs/009-macos-ipad-layout-adaptation/plan.md` — Phase A (Project Setup & Platform Foundation)
- **Research**: `kitty-specs/009-macos-ipad-layout-adaptation/research.md` — §1 (Multi-Platform Target Strategy), §4 (Firebase macOS Support)
- **Constraint**: Single multi-platform target (not a separate macOS target). Same build settings, same source files shared by default.
- **Constraint**: Native SwiftUI macOS — NOT Mac Catalyst
- **Constraint**: No code changes in this WP — purely project configuration

## Subtasks & Detailed Guidance

### Subtask T001 – Add macOS as Supported Destination

- **Purpose**: Enable the Xcode project to build for macOS alongside iOS.
- **Steps**:
  1. Open `LedgeriOS/LedgeriOS.xcodeproj` in Xcode
  2. Select the `LedgeriOS` target → General → Supported Destinations
  3. Click "+" and add "macOS" as a destination
  4. This adds `macosx` to `SUPPORTED_PLATFORMS` in build settings
  5. Alternatively, edit the `.pbxproj` file directly to add `macosx` to `SUPPORTED_PLATFORMS`
  6. Ensure the macOS deployment target is set to macOS 15.0 (aligns with iOS 18+ deployment target)
- **Files**: `LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj`
- **Parallel?**: No — must be done first.
- **Notes**: After this change, SPM will attempt to resolve packages for macOS. UIKit-related build errors will appear — these are expected and fixed in WP02.

### Subtask T002 – Create macOS App Sandbox Entitlements

- **Purpose**: macOS apps distributed via App Store require App Sandbox. Firebase networking requires the `com.apple.security.network.client` entitlement to make outgoing connections from a sandboxed app.
- **Steps**:
  1. Create a new entitlements file at `LedgeriOS/LedgeriOS/LedgeriOS.entitlements` (or check if one already exists)
  2. Add the following keys:
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
  3. In Xcode, assign this entitlements file to the target's "Code Signing Entitlements" build setting (for macOS builds only, or shared if iOS doesn't conflict)
  4. Verify the entitlements file is included in the project navigator
- **Files**: `LedgeriOS/LedgeriOS/LedgeriOS.entitlements` (new file)
- **Parallel?**: Can proceed after T001.
- **Notes**: Without `network.client`, sandboxed macOS builds fail with "Host name resolution failed" when Firebase tries to connect. On iOS, App Sandbox is not used (iOS has its own sandbox model), so this entitlement is macOS-only but harmless to include for both.

### Subtask T003 – Add LSApplicationCategoryType to Info.plist

- **Purpose**: macOS apps need `LSApplicationCategoryType` for App Store categorization. Without it, the app may be rejected or miscategorized.
- **Steps**:
  1. Open `LedgeriOS/LedgeriOS/Info.plist`
  2. Add the key:
     ```xml
     <key>LSApplicationCategoryType</key>
     <string>public.app-category.business</string>
     ```
  3. "Business" is the appropriate category for a project management / inventory tracking tool
  4. This key is ignored on iOS — safe to include unconditionally
- **Files**: `LedgeriOS/LedgeriOS/Info.plist`
- **Parallel?**: Can proceed after T001.
- **Notes**: If Info.plist doesn't exist as a standalone file (may be in build settings), create it or add the key to the appropriate build settings.

### Subtask T004 – Verify SPM Dependencies Resolve for macOS

- **Purpose**: Confirm that all Swift Package Manager dependencies (Firebase Auth, Firestore, Storage, GoogleSignIn-iOS) resolve and link for the macOS target.
- **Steps**:
  1. After adding macOS destination (T001), resolve packages: File → Packages → Resolve Package Versions in Xcode
  2. Or from command line: `xcodebuild -resolvePackageDependencies -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS`
  3. Check that all packages download macOS-compatible binaries
  4. If any package fails to resolve, check its `Package.swift` for macOS platform support
  5. Known: Firebase SDK declares `.macOS(.v10_15)`, GoogleSignIn-iOS declares macOS support
  6. Attempt a build: `xcodebuild -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -destination 'platform=macOS'`
  7. UIKit-related compilation errors are EXPECTED — document them but do not fix (WP02 handles this)
- **Files**: `LedgeriOS/LedgeriOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- **Parallel?**: Must be done after T001.
- **Notes**: If a transitive dependency doesn't support macOS, it may block resolution entirely. In that case, investigate alternatives or exclude the dependency for macOS.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| SPM resolution fails for macOS | Check each package's Platform support. Firebase and GoogleSignIn confirmed macOS-compatible in research.md §4 |
| Entitlements conflict between iOS and macOS | Use build settings to apply entitlements conditionally, or use a single entitlements file (iOS ignores sandbox keys) |
| Missing Info.plist keys cause macOS App Store rejection | Add LSApplicationCategoryType now; other required keys can be added in WP08 polish |

## Review Guidance

- Verify macOS is listed in Supported Destinations in Xcode
- Verify entitlements file exists and contains `app-sandbox` + `network.client`
- Verify SPM resolution completes without errors
- UIKit build errors are expected — do NOT fail the review for them

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP01 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
- 2026-03-01T05:57:59Z – claude – shell_pid=77935 – lane=doing – Assigned agent via workflow command
- 2026-03-01T06:05:05Z – claude – shell_pid=77935 – lane=for_review – Ready for review: macOS target configured — SUPPORTED_PLATFORMS + SDKROOT=auto + MACOSX_DEPLOYMENT_TARGET=15.0 added, entitlements file created, LSApplicationCategoryType added to Info.plist, SPM packages resolve, build starts compilation and produces expected UIKit errors
