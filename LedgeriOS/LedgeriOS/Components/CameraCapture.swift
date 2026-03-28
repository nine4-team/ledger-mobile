#if canImport(UIKit)
import AVFoundation
import SwiftUI

// MARK: - CameraManager

@MainActor
@Observable
final class CameraManager: NSObject {
    var captureCount = 0
    var lastThumbnail: UIImage?
    var showFlash = false
    var isSessionRunning = false
    var permissionDenied = false
    var isAdjustingFocus = false

    @ObservationIgnored
    nonisolated(unsafe) private(set) var session = AVCaptureSession()
    @ObservationIgnored
    nonisolated(unsafe) private var photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored
    nonisolated(unsafe) private var videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored
    nonisolated(unsafe) private var focusObservation: NSKeyValueObservation?
    @ObservationIgnored
    nonisolated(unsafe) private var continuousAFRestoreWork: DispatchWorkItem?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var onCapture: ((Data) -> Void)?

    func checkPermissionAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { configureSession() } else { permissionDenied = true }
        default:
            permissionDenied = true
        }
    }

    func capturePhoto(onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture
        sessionQueue.async { [self] in
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// devicePoint is in normalized camera coordinates (0–1), produced by
    /// AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:).
    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else {
                print("[Camera] focus: no device input found")
                return
            }
            print("[Camera] focus: devicePoint=\(devicePoint), focusSupported=\(device.isFocusPointOfInterestSupported), currentFocusMode=\(device.focusMode.rawValue), isAdjusting=\(device.isAdjustingFocus)")
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    // .autoFocus triggers an immediate single-shot focus operation at the
                    // new point. Setting .continuousAutoFocus when already in that mode is
                    // a no-op — the device sees no state change and does not move the lens.
                    // The KVO callback switches back to .continuousAutoFocus once done.
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                print("[Camera] focus: configuration applied, focusMode=\(device.focusMode.rawValue), isAdjusting=\(device.isAdjustingFocus)")
            } catch {
                print("[Camera] focus: lockForConfiguration failed: \(error)")
                return
            }

            // Signal adjusting before the KVO fires so the indicator appears active immediately
            Task { @MainActor [weak self] in self?.isAdjustingFocus = true }

            // Cancel any pending continuous-AF restore from a previous tap
            continuousAFRestoreWork?.cancel()
            continuousAFRestoreWork = nil

            focusObservation?.invalidate()
            let queue = sessionQueue  // captured to avoid accessing @MainActor property from closure
            focusObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self, queue] captureDevice, change in
                guard let isAdjusting = change.newValue else { return }
                print("[Camera] KVO isAdjustingFocus → \(isAdjusting), lensPosition=\(captureDevice.lensPosition)")

                if !isAdjusting {
                    // One-shot: invalidate so continuous-AF evaluation doesn't re-fire this callback
                    // and recreate the hunting loop (H4).
                    self?.focusObservation?.invalidate()
                    self?.focusObservation = nil
                    // Restore continuous AF after 1s so the lens has time to settle on the subject.
                    // .autoFocus consistently picks 0.0 (wrong). Immediately switch to
                    // .continuousAutoFocus so it re-evaluates with full range and finds
                    // the correct position. The KVO is already invalidated at this point
                    // so there is no risk of recreating the H4 hunting loop.
                    let work = DispatchWorkItem { [weak captureDevice] in
                        guard let device = captureDevice else { return }
                        print("[Camera] continuousAF restore: pre-restore lensPosition=\(device.lensPosition)")
                        if device.isFocusModeSupported(.continuousAutoFocus) {
                            try? device.lockForConfiguration()
                            device.focusMode = .continuousAutoFocus
                            device.unlockForConfiguration()
                        }
                    }
                    self?.continuousAFRestoreWork = work
                    queue.async(execute: work)
                }
                Task { @MainActor [weak self] in self?.isAdjustingFocus = isAdjusting }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureSession() {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            print("[Camera] session: device=\(camera.localizedName), focusMode=\(camera.focusMode.rawValue), focusSupported=\(camera.isFocusPointOfInterestSupported)")

            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed

            // A photo-only session lacks the continuous frame pipeline that contrast-detection
            // AF requires. Adding a discard-only video output provides that pipeline without
            // any processing overhead — no delegate, no stored frames.
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            session.startRunning()

            if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
                print("[Camera] session started: lensPosition=\(device.lensPosition), focusMode=\(device.focusMode.rawValue), focusPoint=\(device.focusPointOfInterest)")
            }

            Task { @MainActor in self.isSessionRunning = true }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.85) else { return }

        let thumbSize = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbnail = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: thumbSize)) }

        Task { @MainActor [weak self] in
            guard let self else { return }
            lastThumbnail = thumbnail
            captureCount += 1
            self.onCapture?(jpegData)
            self.onCapture = nil
            withAnimation(.easeIn(duration: 0.05)) { showFlash = true }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.15)) { showFlash = false }
        }
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
            if manager.isSessionRunning { bottomBar }
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

            Button {
                manager.capturePhoto { data in onCapture(data) }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                    Circle().fill(.white).frame(width: 64, height: 64)
                }
            }
            .buttonStyle(ShutterButtonStyle())

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

// MARK: - ShutterButtonStyle

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
#endif
