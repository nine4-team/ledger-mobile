# Tap-to-Focus Troubleshooting

**File:** `LedgeriOS/LedgeriOS/Components/CameraCapture.swift`
**Started:** 2026-03-28
**Status:** Two bugs remain — `FocusIndicator` not resetting between taps, and suspected coordinate space mismatch causing poor focus accuracy

---

## Symptoms (original)

1. Tap-to-focus rectangle never appeared (0% reliability)
2. When it did rarely appear, focus was partial — camera didn't lock

---

## Hypothesis 1: UITapGestureRecognizer blocked by sibling SwiftUI views

**Theory:** The original implementation added a `UITapGestureRecognizer` on `PreviewView` (the `UIViewRepresentable` backing UIView). UIKit's `hitTest` chain found sibling UIKit-backed SwiftUI overlay views first and dropped the gesture.

**Test:** Observed that gestures never fired reliably.

**Result: Confirmed.** UIKit's hit test is first-come-first-served. The controls `VStack`'s UIKit backing views (and their children's backing views) won every `hitTest` before the recognizer on `PreviewView` got a chance.

**Fix applied:** Removed `UITapGestureRecognizer` from `PreviewView`. Moved gesture to SwiftUI level: `.onTapGesture(coordinateSpace: .local)` on `CameraPreview`.

---

## Hypothesis 2: `.autoFocus` locks mid-travel, causing partial focus

**Theory:** `AVCaptureDevice.FocusMode.autoFocus` is single-shot — it fires, moves the lens, and locks wherever the lens is when the operation completes. If the lens hasn't finished traveling, it locks blurry.

**Result: Confirmed** (known AVFoundation behavior, not tested directly). This was fixed preemptively.

**Fix applied:** Changed to `.continuousAutoFocus` + `.continuousAutoExposure`. Added KVO on `device.isAdjustingFocus` to drive `FocusIndicator` fade timing.

---

## Hypothesis 3: UIViewRepresentable needs `contentShape(Rectangle())` for SwiftUI gestures

**Theory:** Without an explicit `contentShape`, SwiftUI's hit testing system has no declared interaction area for the `UIViewRepresentable` and skips it. This would cause `.onTapGesture` to never fire.

**Test:** Added `.contentShape(Rectangle())` to `CameraPreview`.

**Result: Disproved as sole fix.** Taps still didn't register after this change. The gesture was being blocked upstream before SwiftUI even processed it.

---

## Hypothesis 4: Full-screen VStack's UIKit backing view intercepts all touches at UIKit level

**Theory:** The controls were laid out as:
```swift
ZStack {
    CameraPreview(...).onTapGesture { ... }  // layer 2
    VStack {                                   // layer 3 (topmost)
        topBar
        Spacer().allowsHitTesting(false)
        bottomBar
    }
}
```
`Spacer().allowsHitTesting(false)` is a SwiftUI-level instruction. But the `VStack`'s UIKit backing view covers the full screen. UIKit's `hitTest` runs before SwiftUI processes anything — the full-screen UIKit view intercepts every touch and SwiftUI never reaches the `Spacer`'s pass-through logic.

**Test:** Replaced the full-screen `VStack` with `.overlay(alignment: .top)` and `.overlay(alignment: .bottom)` on the ZStack. These overlays create UIKit backing views sized only to the button areas, leaving the middle of the screen physically clear at UIKit level.

**Result: Partially confirmed.** After this fix, the first tap fired reliably — the focus rectangle appeared. However, two remaining bugs were revealed:
- Bug A: The focus rectangle appears but focus quality is poor
- Bug B: Subsequent taps show nothing (gesture appears to stop firing)

---

## Bug A: Poor focus quality on first tap

**Observed:** Rectangle appears at tap location, but the camera image doesn't visibly sharpen.

**Hypothesis:** Coordinate space mismatch between SwiftUI's `.local` coordinate space and the `AVCaptureVideoPreviewLayer`'s layer coordinate space.

- SwiftUI's `.onTapGesture(coordinateSpace: .local)` reports coordinates in the view's SwiftUI frame. With `.ignoresSafeArea()`, SwiftUI considers (0,0) to be the top-left of the screen.
- However, the UIKit `PreviewView`'s `bounds` may start at the safe area boundary (below the Dynamic Island / notch), not at (0,0) of the screen.
- `captureDevicePointConverted(fromLayerPoint:)` converts from layer coordinates — if the layer's origin doesn't match the SwiftUI coordinate origin, the resulting device point is wrong.
- Example: tapping at SwiftUI coordinate (200, 300) might be passed to `captureDevicePointConverted` as (200, 300), but the layer's actual bounds for that point might be (200, 241) (assuming a 59pt safe area offset). The camera would focus on the wrong area.

**Not yet fixed.**

---

## Bug B: Subsequent taps show nothing

**Observed:** After the focus rectangle appears and fades, all subsequent taps produce no rectangle and no focus activity.

**Root cause identified (not yet fixed):**

The `FocusIndicator` view has `.id(id)` applied INSIDE its `body`, on the `RoundedRectangle`:

```swift
// FocusIndicator.body — WRONG placement
RoundedRectangle(...)
    .opacity(opacity)
    .id(id)  // ← applied to the inner view, not to FocusIndicator itself
```

When `focusId` changes (on second tap), SwiftUI creates a new `FocusIndicator(id: newId, ...)`. Because no `.id()` is applied to `FocusIndicator` itself at the call site, SwiftUI treats it as the SAME view being updated in place. The `@State var opacity` and `@State var scale` are NOT reset — `opacity` remains `0.0` from the previous fade. `.onAppear` does not re-fire.

Result: the indicator renders but is invisible (`opacity = 0`). The focus operation itself likely does run, but there's no visual feedback, and the user believes the tap was ignored.

**Fix (not yet applied):** Apply `.id(focusId)` to `FocusIndicator` EXTERNALLY at the call site in `CameraCapture.body`, forcing view recreation:

```swift
// In CameraCapture.body overlay:
FocusIndicator(id: focusId, isAdjusting: manager.isAdjustingFocus)
    .id(focusId)    // ← forces destruction + recreation, resets @State
    .position(x: point.x, y: point.y)
    .allowsHitTesting(false)
```

---

## Recommended next steps

### Step 1: Fix Bug B (FocusIndicator identity)

Apply `.id(focusId)` externally on `FocusIndicator` at its call site (line ~247 in `CameraCapture.body`). This forces SwiftUI to recreate the view on each tap, resetting `@State opacity` and `@State scale` and re-firing `.onAppear`.

Optionally remove the redundant `.id(id)` from inside `FocusIndicator.body` to avoid confusion.

### Step 2: Fix Bug A (coordinate space)

Option A — **Adjust tap coordinates before conversion.** Get the layer's frame in screen coordinates and offset the SwiftUI tap point:

```swift
.onTapGesture(coordinateSpace: .local) { location in
    guard let layer = previewLayer else { ... }
    // Convert UIView frame to screen coordinates, then offset SwiftUI tap point
    let layerOriginInScreen = layer.convert(CGPoint.zero, to: nil)
    let layerPoint = CGPoint(x: location.x - layerOriginInScreen.x,
                             y: location.y - layerOriginInScreen.y)
    let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: layerPoint)
    manager.focus(at: devicePoint)
}
```

Option B — **Switch back to UIKit gesture on PreviewView, now that the blocking VStack is gone.** The original reason UIKit gestures were abandoned was sibling UIKit views blocking `hitTest`. With the overlay fix in place, there are no longer sibling UIKit views covering the camera area — a `UITapGestureRecognizer` on `PreviewView` would now receive touches. UIKit tap coordinates on the UIView ARE in layer space, so `captureDevicePointConverted` would be called with the correct coordinate system, eliminating the mismatch entirely.

Option B is architecturally cleaner because it removes the coordinate conversion problem at its root.

---

## Current file state

All changes are in `LedgeriOS/LedgeriOS/Components/CameraCapture.swift`.

Key current state:
- `CameraPreview`: `UIViewRepresentable` with `onLayerReady` callback. No gesture. `contentShape(Rectangle())` applied.
- `CameraCapture.body`: `CameraPreview` has `.onTapGesture(coordinateSpace: .local)`. Controls are `.overlay(alignment: .top/bottom)` on the ZStack (not inside).
- `CameraManager.focus(at:)`: uses `.continuousAutoFocus` + `.continuousAutoExposure` + KVO on `isAdjustingFocus`.
- `FocusIndicator`: fades on `isAdjusting` false or 2500ms fallback. Bug: `.id()` applied to inner view, not to self.
