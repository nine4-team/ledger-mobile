import Foundation

/// Temporary lifecycle instrumentation for the stable-ID navigation work.
///
/// Logs are debug-only and prefixed with `[NavLifecycle]` so they are easy to
/// filter and easy to remove. They exist to confirm whether the item-rename /
/// back / menu spinners come from route/view/list identity churn (project,
/// item, list, and image lifecycles restarting) versus intentional loading.
///
/// See docs/plans/stable-id-navigation-first-milestone-plan.md (Phases 1 & 9).
/// This helper is compiled out of release builds.
enum NavLifecycleLog {
    @inline(__always)
    static func log(_ event: @autoclosure () -> String) {
        #if DEBUG
        print("[NavLifecycle] \(event())")
        #endif
    }
}
