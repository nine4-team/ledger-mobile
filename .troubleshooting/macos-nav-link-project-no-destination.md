# Issue: NavigationLink for Project has no matching destination on macOS

**Status:** Resolved
**Opened:** 2026-03-11
**Resolved:** 2026-03-12

## Info
- **Symptom:** Console warning on macOS: "A NavigationLink is presenting a value of type 'Project'/'Item' but there is no matching navigationDestination declaration visible from the location of the link. The link cannot be activated." Tapping project cards (and likely items, spaces, transactions) does nothing on macOS. Affects all navigation types, not just Project.
- **Affected area:** `LedgeriOS/LedgeriOS/Views/MainTabView.swift` (all 4 tabs)

### Background

**Navigation structure:**
- `MainTabView` uses `TabView(selection:)` with `.tabViewStyle(.sidebarAdaptable)` (line 55)
- Each tab wraps content in its own `NavigationStack`
- Projects tab (line 20-26): `NavigationStack { ProjectsListView().navigationDestination(for: Project.self) { ... } }`
- `ProjectsListView` line 52: `NavigationLink(value: project) { ProjectCard(...) }`

**The `.sidebarAdaptable` behavior:**
- On iOS: renders as a standard tab bar — NavigationStack works normally
- On macOS: transforms the TabView into a sidebar-based layout, which changes the navigation hierarchy. The tab content may be placed in a detail column, and the NavigationStack's destination resolution can break because the link and destination end up in different navigation containers.

**Only one NavigationLink(value: Project)** exists in the entire codebase (ProjectsListView:52). The Search tab does NOT navigate to projects.

**Also found:** `ProjectsPlaceholderView.swift` has a duplicate `navigationDestination(for: Project.self)` — likely dead code from early development.

## Experiments

### H1: `.sidebarAdaptable` on macOS reorganizes the navigation hierarchy, making the `navigationDestination` inside the NavigationStack invisible to the NavigationLink
- **Rationale:** `.tabViewStyle(.sidebarAdaptable)` on macOS converts the TabView into a sidebar layout. Apple's documentation notes that "Links search for destinations in any surrounding NavigationStack, then within the same column of a NavigationSplitView." On macOS, the sidebar-adaptable style may place the tab content (including the NavigationLink) in a column where the NavigationStack's destination modifier isn't visible.
- **Experiment:** Remove explicit `NavigationStack` wrapping on macOS via `#if os(macOS)` conditional. On macOS, let `.sidebarAdaptable`'s implicit navigation container handle destination resolution. On iOS, keep explicit `NavigationStack` per tab.
- **Result:** Added `tabNavigationStack()` helper in MainTabView that wraps content in `NavigationStack` on iOS only, passes content through directly on macOS. Both iOS and macOS builds succeed. Awaiting user verification on macOS.
- **Verdict:** Ruled Out — removing NavigationStack produced a different error: "The matching navigationDestination declaration is in the detail column, so it attempts to target the next column."

### H2: `.sidebarAdaptable` creates implicit column navigation that intercepts NavigationLink before inner NavigationStack handles it
- **Rationale:** H1's new error revealed sidebarAdaptable creates a column-based layout. With NavigationStack, column nav can't find destinations (they're inside the stack). Without NavigationStack, column nav finds them but tries to push to a non-existent next column. Neither works — sidebarAdaptable's column navigation fundamentally conflicts with NavigationStack.
- **Experiment:** Replace sidebarAdaptable on macOS with explicit NavigationSplitView (sidebar list + NavigationStack in detail column). This gives the same sidebar UI but with proper stack-based navigation.
- **Result:** User confirmed navigation works on macOS. iOS unchanged.
- **Verdict:** Confirmed

## Resolution
_Do not fill this section until the fix is verified — either by a passing
test/build or by explicit user confirmation. Applying a fix is not verification._

- **Root cause:** `.tabViewStyle(.sidebarAdaptable)` on macOS creates an implicit column-based navigation layout that intercepts `NavigationLink` before the inner `NavigationStack` can handle it. Destinations registered inside the stack are invisible to the column navigation, and destinations outside the stack try to push to a non-existent next column.
- **Fix:** Platform-split MainTabView: macOS uses explicit `NavigationSplitView` (sidebar list + `NavigationStack` in detail column), iOS keeps `TabView` + `NavigationStack` per tab unchanged.
- **Files changed:** `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- **Lessons:** `.tabViewStyle(.sidebarAdaptable)` is fundamentally incompatible with `NavigationStack` + `navigationDestination` on macOS. Use explicit `NavigationSplitView` on macOS instead. The error messages from both approaches together reveal the root cause — neither alone is sufficient.
