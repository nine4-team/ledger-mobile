#if canImport(UIKit)
import AVFoundation
import SwiftUI

// MARK: - CameraEngine

final class CameraEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private var focusObservation: NSKeyValueObservation?
    /// AVCapturePhotoOutput may process multiple requests concurrently. Each request
    /// needs its own delegate/completion and must stay retained until capture finishes.
    private var captureProcessors: [Int64: PhotoCaptureProcessor] = [:]

    var onSessionStarted: (@MainActor () -> Void)?
    var onWillCapture: (@MainActor () -> Void)?
    var onFocusStateChanged: (@MainActor (Bool) -> Void)?
    var onZoomCapabilities: (@MainActor (ZoomCapabilities) -> Void)?

    /// Display-space zoom info. "Display" means what Apple shows users (0.5×, 1×, 2×),
    /// which differs from `AVCaptureDevice.videoZoomFactor` on multi-lens virtual devices
    /// where 1.0 is the widest lens — so display-1× maps to the first switch-over factor.
    struct ZoomCapabilities: Sendable {
        var baseWideFactor: CGFloat  // actual zoom that corresponds to display-1×
        var minDisplayZoom: CGFloat
        var maxDisplayZoom: CGFloat
        var presets: [CGFloat]       // display-space presets, e.g. [0.5, 1, 2]
    }

    func start() {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .photo

            // Use the virtual multi-lens device (what the built-in Camera app uses).
            // Falls back to the raw wide-angle if no multi-lens device is available.
            let camera: AVCaptureDevice? =
                AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

            guard let camera,
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed

            // Opt into Apple's low-latency capture pipeline when the active device
            // supports it. These must be configured before the session starts.
            if photoOutput.isZeroShutterLagSupported {
                photoOutput.isZeroShutterLagEnabled = true
            }
            if photoOutput.isResponsiveCaptureSupported {
                photoOutput.isResponsiveCaptureEnabled = true
            }
            if photoOutput.isFastCapturePrioritizationSupported {
                photoOutput.isFastCapturePrioritizationEnabled = true
            }

            // Video output with active delegate — provides the continuous frame
            // pipeline that the AF system needs on this hardware.
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            session.startRunning()

            if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
                print("[Camera] start: device=\(camera.localizedName), format=\(device.activeFormat.description)")

                try? device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.exposureMode = .continuousAutoExposure
                device.isSubjectAreaChangeMonitoringEnabled = true
                // Start at display-1× (wide lens) on multi-lens devices.
                let baseWide = Self.baseWideFactor(for: device)
                device.videoZoomFactor = min(max(baseWide, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                device.unlockForConfiguration()

                let caps = Self.zoomCapabilities(for: device)
                Task { @MainActor [weak self] in self?.onZoomCapabilities?(caps) }
            }

            // Re-trigger AF when scene changes (combats drift)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(subjectAreaDidChange),
                name: .AVCaptureDeviceSubjectAreaDidChange,
                object: camera
            )

            Task { @MainActor [weak self] in self?.onSessionStarted?() }
        }
    }

    @objc private func subjectAreaDidChange(_ notification: Notification) {
        sessionQueue.async { [self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto(completion: @escaping @MainActor (UIImage, Data) -> Void) {
        sessionQueue.async { [self] in
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            let processor = PhotoCaptureProcessor(
                settings: settings,
                onWillCapture: { [weak self] in self?.onWillCapture?() },
                completion: completion,
                onFinished: { [weak self] uniqueID in
                    self?.sessionQueue.async { [weak self] in
                        self?.captureProcessors[uniqueID] = nil
                    }
                }
            )
            captureProcessors[settings.uniqueID] = processor
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    /// Sets zoom in display space (0.5, 1, 2, …). Clamped to device limits.
    func setDisplayZoom(_ displayFactor: CGFloat, animated: Bool = false) {
        sessionQueue.async { [self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            let baseWide = Self.baseWideFactor(for: device)
            let target = displayFactor * baseWide
            let clamped = min(max(target, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            do {
                try device.lockForConfiguration()
                if animated {
                    device.ramp(toVideoZoomFactor: clamped, withRate: 4.0)
                } else {
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
            } catch { return }
        }
    }

    private static func baseWideFactor(for device: AVCaptureDevice) -> CGFloat {
        // On a virtual multi-lens device, the first switch-over factor is where the
        // wide (1×) lens takes over. Single-lens devices return [] and default to 1.0.
        device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1.0
    }

    private static func zoomCapabilities(for device: AVCaptureDevice) -> ZoomCapabilities {
        let baseWide = baseWideFactor(for: device)
        let minDisplay = device.minAvailableVideoZoomFactor / baseWide
        let maxDisplay = device.maxAvailableVideoZoomFactor / baseWide
        var presets: [CGFloat] = []
        if minDisplay < 0.95 { presets.append(0.5) }
        presets.append(1.0)
        if maxDisplay >= 2.0 { presets.append(2.0) }
        if device.virtualDeviceSwitchOverVideoZoomFactors.count >= 2 {
            let tele = CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors[1]) / baseWide
            if tele >= 2.5, !presets.contains(where: { abs($0 - tele) < 0.1 }) {
                presets.append(tele.rounded())
            }
        }
        return ZoomCapabilities(
            baseWideFactor: baseWide,
            minDisplayZoom: minDisplay,
            maxDisplayZoom: maxDisplay,
            presets: presets
        )
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }

            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                // Disable monitoring during tap — re-enabled when AF settles
                device.isSubjectAreaChangeMonitoringEnabled = false
                device.unlockForConfiguration()
            } catch { return }

            Task { @MainActor [weak self] in self?.onFocusStateChanged?(true) }

            focusObservation?.invalidate()
            focusObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] dev, change in
                guard let isAdjusting = change.newValue, !isAdjusting else { return }
                self?.sessionQueue.async { [weak self] in
                    self?.focusObservation?.invalidate()
                    self?.focusObservation = nil
                    // Re-enable monitoring so drift triggers re-focus
                    try? dev.lockForConfiguration()
                    dev.isSubjectAreaChangeMonitoringEnabled = true
                    dev.unlockForConfiguration()
                }
                Task { @MainActor [weak self] in self?.onFocusStateChanged?(false) }
            }
        }
    }
}

// MARK: - PhotoCaptureProcessor

/// Per-request delegate. A single shared completion is unsafe because photo output
/// can have several captures in flight at once (especially with responsive capture).
private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let uniqueID: Int64
    private let requestTime = ProcessInfo.processInfo.systemUptime
    private let onWillCapture: @MainActor () -> Void
    private let completion: @MainActor (UIImage, Data) -> Void
    private let onFinished: @Sendable (Int64) -> Void

    init(
        settings: AVCapturePhotoSettings,
        onWillCapture: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor (UIImage, Data) -> Void,
        onFinished: @escaping @Sendable (Int64) -> Void
    ) {
        uniqueID = settings.uniqueID
        self.onWillCapture = onWillCapture
        self.completion = completion
        self.onFinished = onFinished
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        let latency = Int((ProcessInfo.processInfo.systemUptime - requestTime) * 1_000)
        print("[Camera] shutter latency=\(latency)ms id=\(uniqueID)")
        Task { @MainActor [onWillCapture] in onWillCapture() }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            if let error { print("[Camera] processing failed id=\(uniqueID): \(error)") }
            return
        }

        let thumbSize = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbnail = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: thumbSize)) }
        let latency = Int((ProcessInfo.processInfo.systemUptime - requestTime) * 1_000)
        print("[Camera] processing latency=\(latency)ms id=\(uniqueID)")

        Task { @MainActor [completion] in completion(thumbnail, jpegData) }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error { print("[Camera] capture failed id=\(uniqueID): \(error)") }
        onFinished(uniqueID)
    }
}

// MARK: - CameraEngine + AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // No-op — frame pipeline activation only
    }
}

// MARK: - CameraManager

@MainActor
@Observable
final class CameraManager {
    var isSessionRunning = false
    var captureCount = 0
    var lastThumbnail: UIImage?
    var showFlash = false
    var permissionDenied = false
    var isAdjustingFocus = false

    /// Current zoom in display space (0.5, 1, 2, …).
    var displayZoom: CGFloat = 1.0
    var zoomPresets: [CGFloat] = [1.0]
    var minDisplayZoom: CGFloat = 1.0
    var maxDisplayZoom: CGFloat = 1.0

    private let engine = CameraEngine()
    private var flashSequence = 0

    var session: AVCaptureSession { engine.session }

    init() {
        engine.onSessionStarted = { [weak self] in
            self?.isSessionRunning = true
        }
        engine.onWillCapture = { [weak self] in
            self?.showShutterFlash()
        }
        engine.onFocusStateChanged = { [weak self] isAdjusting in
            self?.isAdjustingFocus = isAdjusting
        }
        engine.onZoomCapabilities = { [weak self] caps in
            guard let self else { return }
            zoomPresets = caps.presets
            minDisplayZoom = caps.minDisplayZoom
            maxDisplayZoom = caps.maxDisplayZoom
            displayZoom = 1.0
        }
    }

    private func showShutterFlash() {
        flashSequence += 1
        let sequence = flashSequence
        withAnimation(.easeIn(duration: 0.05)) { showFlash = true }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, sequence == flashSequence else { return }
            withAnimation(.easeOut(duration: 0.15)) { showFlash = false }
        }
    }

    func setDisplayZoom(_ factor: CGFloat, animated: Bool = false) {
        let clamped = min(max(factor, minDisplayZoom), maxDisplayZoom)
        displayZoom = clamped
        engine.setDisplayZoom(clamped, animated: animated)
    }

    func checkPermissionAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            engine.start()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { engine.start() } else { permissionDenied = true }
        default:
            permissionDenied = true
        }
    }

    func capturePhoto(onCapture: @escaping (Data) -> Void) {
        engine.capturePhoto { [weak self] thumbnail, data in
            guard let self else { return }
            lastThumbnail = thumbnail
            captureCount += 1
            onCapture(data)
        }
    }

    func focus(at devicePoint: CGPoint) {
        engine.focus(at: devicePoint)
    }

    func stopSession() {
        engine.stop()
    }
}

// MARK: - CameraPreview

/// Pure display view. Tap handling via UITapGestureRecognizer on PreviewView so that
/// coordinate conversion happens in the Coordinator — where the layer is guaranteed
/// to exist and have its bounds set, eliminating the need for a @State layer reference.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Called with (viewPoint, devicePoint): viewPoint for the visual indicator position,
    /// devicePoint in normalized camera coordinates (0–1) for AVCaptureDevice focus.
    var onTap: ((CGPoint, CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Keep the coordinator's closure current on every SwiftUI render pass.
        context.coordinator.onTap = onTap
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject {
        var onTap: ((CGPoint, CGPoint) -> Void)?

        init(onTap: ((CGPoint, CGPoint) -> Void)?) { self.onTap = onTap }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewView else { return }
            let viewPoint = recognizer.location(in: view)
            // captureDevicePointConverted accounts for resizeAspectFill crop and produces
            // normalized (0–1) camera coordinates. The layer is guaranteed to have bounds
            // here since the user can only tap a visible preview.
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onTap?(viewPoint, devicePoint)
        }
    }
}

// MARK: - FocusIndicator

private struct FocusIndicator: View {
    let isAdjusting: Bool

    @State private var scale: CGFloat = 1.25
    @State private var opacity: Double = 1.0
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 68, height: 68)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                opacity = 1.0
                scale = 1.25
                withAnimation(.easeOut(duration: 0.15)) { scale = 1.0 }
                // Fallback: always fade at 2.5s in case KVO doesn't fire
                fadeTask = Task {
                    try? await Task.sleep(for: .milliseconds(2500))
                    withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
                }
            }
            .onDisappear { fadeTask?.cancel() }
            .onChange(of: isAdjusting) { _, adjusting in
                guard !adjusting else { return }
                // Focus locked — hold briefly then fade
                fadeTask?.cancel()
                fadeTask = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
                }
            }
    }
}

// MARK: - CameraCapture

struct CameraCapture: View {
    var onCapture: (Data) -> Void
    var onDismiss: () -> Void

    @State private var manager = CameraManager()
    /// Tap location in UIKit/layer coordinate space (from UITapGestureRecognizer on PreviewView).
    @State private var focusPoint: CGPoint?
    /// Changing this UUID forces FocusIndicator to re-create and re-animate.
    @State private var focusId = UUID()
    /// Zoom at the start of the current pinch gesture — pinch is multiplicative against this.
    @State private var pinchBaseZoom: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if manager.isSessionRunning {
                CameraPreview(
                    session: manager.session,
                    onTap: { viewPoint, devicePoint in
                        // viewPoint drives the indicator position; devicePoint is already
                        // in normalized camera coordinates from the Coordinator.
                        focusPoint = viewPoint
                        focusId = UUID()
                        manager.focus(at: devicePoint)
                    }
                )
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = pinchBaseZoom ?? manager.displayZoom
                            if pinchBaseZoom == nil { pinchBaseZoom = base }
                            manager.setDisplayZoom(base * value.magnification)
                        }
                        .onEnded { _ in pinchBaseZoom = nil }
                )
                .overlay {
                    // Overlay shares CameraPreview's coordinate space; UIKit tap
                    // coordinates match, so focusPoint maps directly to .position.
                    if let point = focusPoint {
                        FocusIndicator(isAdjusting: manager.isAdjustingFocus)
                            .id(focusId)  // forces destruction+recreation → resets @State opacity/scale
                            .position(x: point.x, y: point.y)
                            .allowsHitTesting(false)
                    }
                }
            }

            if manager.showFlash {
                Color.white.ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if manager.permissionDenied {
                permissionDeniedView
            }

        }
        // Controls are overlays anchored to top/bottom, not a full-screen VStack.
        // A full-screen VStack's UIKit backing view intercepts all touches before
        // SwiftUI can pass them through — overlays only cover the button areas.
        .overlay(alignment: .top) {
            if manager.isSessionRunning { topBar }
        }
        .overlay(alignment: .bottom) {
            if manager.isSessionRunning {
                VStack(spacing: Spacing.md) {
                    if manager.zoomPresets.count > 1 { zoomBar }
                    bottomBar
                }
            }
        }
        .task { await manager.checkPermissionAndStart() }
        .onDisappear { manager.stopSession() }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if manager.captureCount == 0 {
                Button("Cancel") { onDismiss() }
                    .font(Typography.button)
                    .foregroundStyle(.white)
            }
            Spacer()
            if manager.captureCount > 0 {
                Button { onDismiss() } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("Done").font(Typography.button)
                        Text("\(manager.captureCount)")
                            .font(Typography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BrandColors.primary)
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Zoom Bar

    private var zoomBar: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(manager.zoomPresets, id: \.self) { preset in
                zoomButton(preset: preset)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.black.opacity(0.4), in: Capsule())
    }

    private func zoomButton(preset: CGFloat) -> some View {
        let isActive = abs(manager.displayZoom - preset) < 0.05
        return Button {
            manager.setDisplayZoom(preset, animated: true)
        } label: {
            Text(zoomLabel(for: preset, isActive: isActive))
                .font(.system(size: isActive ? 13 : 11, weight: .semibold))
                .foregroundStyle(isActive ? BrandColors.primary : .white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(isActive ? 0.15 : 0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func zoomLabel(for preset: CGFloat, isActive: Bool) -> String {
        // Active preset shows the live zoom with ×; inactive shows the preset value.
        if isActive {
            let z = manager.displayZoom
            let formatted = z < 1 ? String(format: "%.1f", z) : (z.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(z))" : String(format: "%.1f", z))
            return "\(formatted)×"
        }
        return preset < 1 ? String(format: "%.1f", preset) : "\(Int(preset))"
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if let thumb = manager.lastThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                    .overlay(RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                        .stroke(.white.opacity(0.3), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: manager.captureCount)
            } else {
                Color.clear.frame(width: 48, height: 48)
            }

            Spacer()

            ShutterButton {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                manager.capturePhoto { data in onCapture(data) }
            }

            Spacer()

            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.xxl)
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.5))
            Text("Camera Access Required")
                .font(Typography.h2)
                .foregroundStyle(.white)
            Text("Allow camera access in Settings to take photos.")
                .font(Typography.small)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.md) {
                Button("Cancel") { onDismiss() }
                    .font(Typography.button)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(Typography.button)
                .foregroundStyle(BrandColors.primary)
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.xl)
    }
}

// MARK: - ShutterButton

/// Fires on touch-down rather than touch-up. Apple recommends issuing photo capture
/// as early as possible to reduce shutter lag and camera shake from the tap itself.
private struct ShutterButton: View {
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
            Circle().fill(.white).frame(width: 64, height: 64)
        }
        .contentShape(Circle())
        .scaleEffect(isPressed ? 0.85 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, pressed, _ in pressed = true }
        )
        .onChange(of: isPressed) { wasPressed, isPressed in
            if isPressed && !wasPressed { action() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Take Photo")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
#endif
