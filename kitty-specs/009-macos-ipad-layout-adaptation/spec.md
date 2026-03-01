# macOS + iPad Layout Adaptation

## Overview

Add a native SwiftUI macOS target to the existing Ledger iOS project and adapt all screens to work across iPhone, iPad, and Mac from a single shared codebase. The iOS app (198 Swift files, fully functional) becomes the foundation — macOS and iPad get adapted navigation, layout, and platform-native chrome on top of the existing views, models, and services.

## Motivation

Ledger is a project management and inventory tracking tool used by people who work at desks (Mac) and on-site (iPhone/iPad). Providing a native Mac experience lets users manage projects, review budgets, and process transactions on a larger screen with keyboard-driven workflows — without maintaining a separate web app or Electron wrapper. iPad support follows naturally from the same adaptive layout work.

## Actors

- **Owner/Admin** — Primary user managing projects, budgets, transactions, items, and spaces across all devices
- **Team Member** — Invited user with read or write access, using the app on any device

## Functional Requirements

### FR-1: Native macOS Target

The Xcode project must include a native SwiftUI macOS destination (not Mac Catalyst). The macOS app must:

- Launch, authenticate, and connect to the same Firebase backend as the iOS app
- Share all models, services, state management, and business logic with the iOS target
- Have its own Firebase Console registration and `GoogleService-Info.plist` appropriate for the macOS bundle identifier
- Support Google Sign-In using the macOS-native presentation mechanism (NSWindow) instead of UIViewController

### FR-2: Adaptive Navigation — Sidebar on Mac/iPad, Tabs on iPhone

The app must use a single navigation architecture that adapts by platform:

- **Mac and iPad (regular width)**: `NavigationSplitView` with a sidebar listing the four main sections (Projects, Inventory, Search, Settings). Selecting a section shows its content in the detail area. The sidebar is always visible on Mac; on iPad it can be toggled.
- **iPhone (compact width)**: The existing `TabView` with four tabs. No sidebar. Current navigation behavior preserved exactly.
- The transition between sidebar and tab layouts must be driven by horizontal size class, not by OS detection, so iPad in portrait (compact) shows tabs and iPad in landscape (regular) shows the sidebar.

### FR-3: Window Toolbar with Account Selector (macOS)

On macOS, the window toolbar must include an account selector that lets the user switch between accounts without navigating to Settings:

- Displays the current account name in the toolbar
- Opens a dropdown/menu showing all discovered accounts
- Selecting an account switches context immediately (same behavior as the existing `AccountGateView` flow)
- On iOS/iPad, the existing account selection flow (AccountGateView sheet, Settings > Switch Account) remains unchanged

### FR-4: Multiple Window Support (macOS)

The macOS app must support multiple simultaneous windows:

- Users can open additional windows via File > New Window (or Cmd+N when no creation context is active)
- Each window maintains its own navigation state (selected sidebar item, detail view)
- All windows share the same authenticated session and account context
- Creating or editing data in one window is reflected in all other windows (via existing Firestore real-time subscriptions)

### FR-5: Keyboard Shortcuts

The macOS app must provide keyboard shortcuts for common actions, surfaced through a standard Mac menu bar:

- **Cmd+N** — Create new (context-sensitive: new project from Projects list, new transaction from Transactions tab, new item from Items tab)
- **Cmd+F** — Focus the search field (universal search or in-list search, depending on context)
- **Cmd+,** — Navigate to Settings (in sidebar, not a separate window)
- Standard system shortcuts must work: Cmd+C/V/X (copy/paste/cut in text fields), Cmd+Z (undo), Cmd+W (close window), Cmd+Q (quit)

The menu bar must include at minimum: File (New, Close Window), Edit (standard text editing), View (Toggle Sidebar), and application-standard items. Custom menus beyond these basics are not required.

### FR-6: Adaptive Card Layouts for Wider Screens

All card-based views must adapt to wider screens without looking stretched or sparse:

- **List views** (Projects, Transactions, Items, Spaces): Cards should have a comfortable maximum width or use a multi-column grid on wide screens rather than stretching to fill a 1440px Mac window edge-to-edge
- **Detail views** (Project Detail, Transaction Detail, Item Detail, Space Detail): Content sections should use a readable maximum width with centered alignment on wide screens
- **Form sheets**: On Mac, sheets should present as fixed-width panels (not stretch to window width). On iPad, existing `.presentationDetents` behavior is preserved.
- **Dashboard/budget views**: Budget progress bars, category cards, and report views should use available width intelligently (e.g., multi-column category grids)

### FR-7: Minimum Window Size (macOS)

The macOS app must enforce a minimum window size to prevent layouts from breaking:

- Minimum width and height must be set to values that ensure all views remain usable
- The sidebar must remain functional at minimum width
- Content area must have enough room to display detail views without truncation

### FR-8: Cross-Platform GoogleSignIn

Google Sign-In must work on both iOS and macOS:

- On iOS: Continue using the existing `UIViewController`-based presentation
- On macOS: Use the `NSWindow`-based presentation provided by the GoogleSignIn macOS SDK
- The `AuthManager` must abstract this platform difference so that sign-in/sign-out flows work identically from the user's perspective

## User Scenarios & Testing

### Scenario 1: First Launch on Mac

A user who already uses Ledger on iPhone downloads the Mac app. They sign in with Google, select their account, and see the sidebar with Projects selected. Their projects list loads from Firestore (cache-first). They click a project and see the detail view in the content area. The sidebar remains visible.

**Acceptance**: User completes sign-in, sees sidebar navigation, and can browse projects without errors.

### Scenario 2: Multi-Window Workflow on Mac

A user opens a second window (Cmd+N or File > New Window). In window 1 they have Project A's transaction list open. In window 2 they navigate to Project B's items. They create a new item in window 2 — it appears in the items list. They switch to window 1 and navigate to Project B — the new item is visible there too.

**Acceptance**: Two windows operate independently. Data changes propagate across windows in real time.

### Scenario 3: iPad Landscape to Portrait Transition

A user is using the app on iPad in landscape orientation. They see the sidebar on the left with Projects selected and the projects list in the detail area. They rotate to portrait — the sidebar disappears and they see a tab bar at the bottom with four tabs. They tap the Inventory tab and see the inventory screen. They rotate back to landscape — the sidebar reappears with Inventory selected.

**Acceptance**: Navigation mode switches cleanly between sidebar (landscape) and tabs (portrait). Selected section is preserved across rotations.

### Scenario 4: Keyboard-Driven Project Creation on Mac

A user is viewing the Projects list. They press Cmd+N. The New Project sheet appears. They fill in the form using Tab to move between fields and Return to submit. The new project appears in the list.

**Acceptance**: Cmd+N triggers the correct creation flow based on context. Form is keyboard-navigable.

### Scenario 5: Account Switching via Mac Toolbar

A user has two accounts. They click the account name in the Mac window toolbar. A dropdown shows both accounts. They select the other account. The sidebar content refreshes to show that account's data.

**Acceptance**: Account selector is visible in the toolbar. Switching accounts refreshes all data without requiring navigation to Settings.

### Scenario 6: Wide Screen Card Layout

A user has a 27" iMac with the app window maximized. The projects list shows cards at a comfortable reading width (not stretched edge-to-edge across 2560px). Opening a project detail, the content is centered with readable line lengths. Budget cards may arrange in multiple columns.

**Acceptance**: No view stretches uncomfortably on wide screens. Content has reasonable maximum widths.

### Scenario 7: iPhone Experience Unchanged

A user opens the app on iPhone SE (smallest supported) and iPhone 15 Pro Max (largest). The existing tab-based navigation works exactly as before Phase 6. No sidebar appears. No layout regressions.

**Acceptance**: All existing iPhone screens render correctly with no visual or behavioral changes from pre-Phase 6 behavior.

## Key Entities

No new data entities are introduced. All existing Firestore models (Project, Transaction, Item, Space, Account, etc.) are shared across platforms.

**New UI-level constructs**:
- Sidebar section list (Projects, Inventory, Search, Settings) — view-layer only, no model
- Window-level navigation state (selected section, detail path) — per-window `@State`/`@SceneStorage`
- Account toolbar selector — view-layer only, reads existing `AccountContext`

## Constraints

- **Shared codebase**: iOS and macOS must share ~90% of code. Platform-specific code is isolated behind `#if os(iOS)` / `#if os(macOS)` conditionals or horizontal size class checks.
- **No UIKit on macOS**: The macOS target must not import UIKit. Any UIKit usage (currently only `AuthManager.swift`) must be conditionally compiled.
- **Existing behavior preserved**: All iPhone screens must continue to work exactly as they do today. Phase 6 is additive — no regressions on iPhone.
- **Firebase SDK compatibility**: All SPM dependencies (Firebase Auth, Firestore, Storage, GoogleSignIn) are already macOS-compatible. No dependency changes expected.
- **Offline-first preserved**: macOS and iPad must follow the same offline-first principles as iOS — no spinners of doom, optimistic UI, Firestore cache-first reads.

## Assumptions

- The existing Firebase project can register a macOS app alongside the iOS app without conflicts (standard Firebase multi-platform setup).
- GoogleSignIn-iOS SPM package (v7+) includes macOS support and provides an `NSWindow`-based sign-in flow.
- SwiftUI `NavigationSplitView` with size-class-driven switching is stable and sufficient for the sidebar/tab adaptive pattern (no custom container needed).
- The existing `.sheet()` / `.presentationDetents()` modal system works acceptably on macOS (sheets present as Mac-native sheets attached to the window).
- Multi-window support via SwiftUI's `WindowGroup` works with the existing `@Observable` state management pattern — each window gets its own navigation state but shares global state (auth, account context) via the environment.

## Dependencies

- **Phases 1–5 complete**: All iOS screens, components, models, and services are built and working (confirmed complete per migration plan).
- **Apple Developer account**: macOS app ID and provisioning profile must be configured.
- **Firebase Console access**: To register the macOS app and download its `GoogleService-Info.plist`.

## Risks

- **NavigationSplitView edge cases**: Adaptive sidebar-to-tab switching may have edge cases around deep navigation state preservation during orientation changes on iPad. Requires thorough testing.
- **Multi-window state isolation**: Ensuring each window has independent navigation state while sharing data state may surface unexpected SwiftUI lifecycle issues.
- **Sheet presentation on macOS**: SwiftUI sheets on macOS behave differently than iOS (attached to window, no detents). Some bottom-sheet-heavy flows may need macOS-specific presentation adjustments.
- **GoogleSignIn macOS API differences**: The macOS sign-in flow may have different error handling or configuration requirements than iOS.

## Success Criteria

- All existing iPhone screens continue to work identically on iPhone SE through iPhone 15 Pro Max with no visual or behavioral regressions
- Users on iPad can navigate the app using either sidebar (landscape/regular width) or tabs (portrait/compact width) with section selection preserved across orientation changes
- Users on Mac can sign in, browse all sections, create/edit/delete data, and use keyboard shortcuts without touching the mouse for common actions
- Users on Mac can open multiple windows and work with different projects simultaneously, with data changes reflected across all windows within 5 seconds
- No screen or card stretches uncomfortably on displays up to 27" — all content maintains readable widths
- The macOS app launches and reaches the main screen within 5 seconds on a standard Mac
- A single codebase produces both the iOS and macOS apps with no code duplication between targets
