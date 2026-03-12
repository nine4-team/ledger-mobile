#if canImport(UIKit)
import AVFoundation
import SwiftUI

// MARK: - CameraManager

/// Manages AVCaptureSession for multi-shot photo capture.
/// All session work runs on a dedicated serial queue; UI state updates dispatch to @MainActor.
@MainActor
@Observable
final class CameraManager: NSObject {
    var captureCount = 0
    var lastThumbnail: UIImage?
    var showFlash = false
    var isSessionRunning = false
    var permissionDenied = false

    private(set) var session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var onCapture: ((Data) -> Void)?

    func checkPermissionAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                configureSession()
            } else {
                permissionDenied = true
            }
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

    func stopSession() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureSession() {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .photo

            // Camera input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            // Photo output
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed

            session.commitConfiguration()
            session.startRunning()

            Task { @MainActor in
                self.isSessionRunning = true
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: @preconcurrency AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.85) else { return }

        // Generate small thumbnail on background thread
        let thumbSize = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastThumbnail = thumbnail
            self.captureCount += 1
            self.onCapture?(jpegData)
            self.onCapture = nil

            // Flash feedback
            withAnimation(.easeIn(duration: 0.05)) {
                self.showFlash = true
            }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.15)) {
                self.showFlash = false
            }
        }
    }
}

// MARK: - CameraPreview

/// Displays the live camera feed from an AVCaptureSession.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - CameraCapture

/// Multi-shot camera. Takes photos continuously until the user taps Done.
/// Each captured photo fires `onCapture` immediately with JPEG data.
/// The camera stays open between shots.
struct CameraCapture: View {
    var onCapture: (Data) -> Void
    var onDismiss: () -> Void

    @State private var manager = CameraManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if manager.isSessionRunning {
                CameraPreview(session: manager.session)
                    .ignoresSafeArea()
            }

            // Flash overlay
            if manager.showFlash {
                Color.white.ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Permission denied state
            if manager.permissionDenied {
                permissionDeniedView
            }

            // Controls overlay
            if manager.isSessionRunning {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
            }
        }
        .task {
            await manager.checkPermissionAndStart()
        }
        .onDisappear {
            manager.stopSession()
        }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if manager.captureCount == 0 {
                Button("Cancel") {
                    onDismiss()
                }
                .font(Typography.button)
                .foregroundStyle(.white)
            }

            Spacer()

            if manager.captureCount > 0 {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("Done")
                            .font(Typography.button)
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
            // Thumbnail of last capture
            if let thumb = manager.lastThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: manager.captureCount)
            } else {
                Color.clear.frame(width: 48, height: 48)
            }

            Spacer()

            // Shutter button
            Button {
                manager.capturePhoto { data in
                    onCapture(data)
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                }
            }
            .buttonStyle(ShutterButtonStyle())

            Spacer()

            // Balance spacer
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
                Button("Cancel") {
                    onDismiss()
                }
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
